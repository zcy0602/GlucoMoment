// 稳糖食刻 — 食物识别代理 · Node.js HTTP 服务
// 用法：npm run dev:server  或  npm run build:server && npm run start:server

import "dotenv/config";
import express, { type Request, type Response } from "express";
import multer from "multer";
import { rateLimit } from "express-rate-limit";
import { randomUUID } from "node:crypto";

import {
  CoreConfig,
  ClientInputError,
  PROMPT_VERSION,
  MAX_IMAGE_BYTES,
  MAX_IMAGE_COUNT,
  MAX_TOTAL_IMAGE_BYTES,
  SYSTEM_PROMPT,
  resolveProvider,
  buildUserPrompt,
  buildUserContent,
  cleanText,
  parseModelJSON,
  validateAnalysis,
  uint8ArrayToBase64,
} from "./core";

// ---- 配置 ----

function loadConfig(): CoreConfig {
  return {
    FOOD_AI_PROVIDER: (process.env.FOOD_AI_PROVIDER as "qwen" | "glm") || "qwen",
    FOOD_AI_MODEL: process.env.FOOD_AI_MODEL,
    AI_BASE_URL: process.env.AI_BASE_URL,
    QWEN_API_KEY: process.env.QWEN_API_KEY,
    GLM_API_KEY: process.env.GLM_API_KEY,
  };
}

// ---- Express App ----

const app = express();
const config = loadConfig();
const port = parseInt(process.env.PORT || "8787", 10);

// 安全头
app.disable("x-powered-by");
app.use((_req, res, next) => {
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("Cache-Control", "no-store");
  next();
});

// IP 限流：10 次/分钟
const limiter = rateLimit({
  windowMs: 60_000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { message: "请求过于频繁，请稍后再试。" },
  statusCode: 429,
});
app.use(limiter);

// multipart 解析：只接受 image 字段，最多 MAX_IMAGE_COUNT 张，每张最大 8MB
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_IMAGE_BYTES, files: MAX_IMAGE_COUNT },
  fileFilter: (_req, file, cb) => {
    if (!file.mimetype.startsWith("image/")) {
      cb(new ClientInputError("仅支持图片文件。"));
      return;
    }
    cb(null, true);
  },
}).array("image", MAX_IMAGE_COUNT);

// ---- 路由 ----

app.get("/health", (_req: Request, res: Response) => {
  res.json({ status: "ok", promptVersion: PROMPT_VERSION });
});

app.post("/v1/food/analyze", (req: Request, res: Response) => {
  upload(req, res, async (err) => {
    const requestId =
      (req.headers["x-request-id"] as string) || randomUUID();

    try {
      // multer 错误
      if (err) {
        const status = err instanceof ClientInputError ? 415 : 422;
        // multer 对“image 超过张数”和“字段名不是 image”都报 LIMIT_UNEXPECTED_FILE，用字段名区分
        const multerError = err instanceof multer.MulterError ? err : undefined;
        const tooManyImages =
          multerError?.code === "LIMIT_FILE_COUNT" ||
          (multerError?.code === "LIMIT_UNEXPECTED_FILE" &&
            multerError.field === "image");
        const unexpectedField =
          multerError?.code === "LIMIT_UNEXPECTED_FILE" && !tooManyImages;
        const message = tooManyImages
          ? `一次最多上传 ${MAX_IMAGE_COUNT} 张照片。`
          : unexpectedField
            ? "图片字段名必须为 image。"
            : err instanceof ClientInputError
            ? err.message
            : "图片无效或超过 8MB。";
        res.status(status).json({ message, requestId });
        return;
      }

      const files = Array.isArray(req.files) ? req.files : [];
      if (files.length === 0 || files.some((file) => file.size === 0)) {
        res.status(422).json({ message: "图片无效或超过 8MB。", requestId });
        return;
      }
      const totalBytes = files.reduce((sum, file) => sum + file.size, 0);
      if (totalBytes > MAX_TOTAL_IMAGE_BYTES) {
        res.status(422).json({ message: "照片总大小超过 20MB。", requestId });
        return;
      }

      const context = cleanText(req.body?.userFoodContext, 500);
      const mealPeriod = cleanText(req.body?.mealPeriod, 20);
      const locale = cleanText(req.body?.locale, 30) || "zh-CN";
      const provider = config.FOOD_AI_PROVIDER || "qwen";
      const providerConfig = resolveProvider(
        provider as "qwen" | "glm",
        config,
      );
      const uploadedImages = files.map((file) => ({
        mimeType: file.mimetype,
        base64: uint8ArrayToBase64(file.buffer),
      }));

      const upstreamResponse = await fetch(providerConfig.baseURL, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${providerConfig.apiKey}`,
          "Content-Type": "application/json",
          "X-Client-Request-Id": requestId,
        },
        body: JSON.stringify({
          model: providerConfig.model,
          messages: [
            { role: "system", content: SYSTEM_PROMPT },
            {
              role: "user",
              content: buildUserContent(
                uploadedImages,
                buildUserPrompt(context, mealPeriod, uploadedImages.length, locale),
              ),
            },
          ],
          response_format: { type: "json_object" },
          enable_thinking: false,
          temperature: 0.1,
          max_completion_tokens: 2500,
        }),
      });

      if (!upstreamResponse.ok) {
        const status =
          upstreamResponse.status === 429 ? 429 : 502;
        const message =
          upstreamResponse.status === 429
            ? "模型服务繁忙，请稍后再试。"
            : "模型服务暂时不可用。";
        res.status(status).json({ message, requestId });
        return;
      }

      const upstream = (await upstreamResponse.json()) as {
        choices?: Array<{ message?: { content?: string } }>;
      };
      const content = upstream.choices?.[0]?.message?.content;
      if (!content) {
        res
          .status(502)
          .json({ message: "模型没有返回可用结果。", requestId });
        return;
      }

      const analysis = validateAnalysis(parseModelJSON(content));
      res.json({
        requestId,
        schemaVersion: 1,
        provider,
        model: providerConfig.model,
        promptVersion: PROMPT_VERSION,
        ...analysis,
      });
    } catch (error) {
      const message =
        error instanceof ClientInputError
          ? error.message
          : "食物识别服务暂时不可用。";
      const status = error instanceof ClientInputError ? 422 : 500;
      res.status(status).json({ message, requestId });
    }
  });
});

// 404 兜底
app.use((_req: Request, res: Response) => {
  res.status(404).json({ message: "Not found" });
});

// ---- 启动 ----

app.listen(port, () => {
  console.log(`稳糖食刻食物识别代理已启动 → http://localhost:${port}`);
  console.log(`Provider: ${config.FOOD_AI_PROVIDER || "qwen"}`);
  console.log(
    `Model: ${config.FOOD_AI_MODEL || (config.FOOD_AI_PROVIDER === "glm" ? "glm-4.6v-flash" : "qwen3.7-plus")}`,
  );
});
