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
  SYSTEM_PROMPT,
  resolveProvider,
  buildUserPrompt,
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

// multipart 解析：只接受 image 字段，最大 8MB
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_IMAGE_BYTES, files: 1 },
  fileFilter: (_req, file, cb) => {
    if (!file.mimetype.startsWith("image/")) {
      cb(new ClientInputError("仅支持图片文件。"));
      return;
    }
    cb(null, true);
  },
}).single("image");

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
        res
          .status(status)
          .json({ message: err.message || "图片无效或超过 8MB。", requestId });
        return;
      }

      if (!req.file) {
        res.status(422).json({ message: "图片无效或超过 8MB。", requestId });
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
      const imageBase64 = uint8ArrayToBase64(req.file.buffer);

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
              content: [
                {
                  type: "image_url",
                  image_url: {
                    url: `data:${req.file.mimetype};base64,${imageBase64}`,
                  },
                },
                {
                  type: "text",
                  text: buildUserPrompt(context, mealPeriod, locale),
                },
              ],
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
