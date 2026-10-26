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
  CORRECTION_PROMPT_VERSION,
  REVIEW_PROMPT_VERSION,
  MAX_IMAGE_BYTES,
  MAX_IMAGE_COUNT,
  MAX_TOTAL_IMAGE_BYTES,
  MAX_CORRECTION_LENGTH,
  SYSTEM_PROMPT,
  CORRECTION_SYSTEM_PROMPT,
  REVIEW_SYSTEM_PROMPT,
  resolveProvider,
  buildUserPrompt,
  buildUserContent,
  buildCorrectionUserPrompt,
  buildReviewUserPrompt,
  cleanText,
  parseModelJSON,
  parseCorrectionRecord,
  parseCorrectionHistory,
  parseReviewPayload,
  validateAnalysis,
  validateCorrection,
  validateReview,
  uint8ArrayToBase64,
  type UploadedImage,
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

// 线上由同机的 Nginx 反向代理转发（见 README）。只信任来自本机回环地址的 X-Forwarded-For，
// 这样限流按用户的真实 IP 计算；直接访问时仍按连接地址计算，外部伪造的请求头不起作用
app.set("trust proxy", "loopback");

// IP 限流：每个 IP 30 次/分钟。会场多台手机可能共用一个出口 IP，一次完整演示约 5 次请求
const limiter = rateLimit({
  windowMs: 60_000,
  max: 30,
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

// 上游模型返回的错误，status 与 message 直接转给 App
class UpstreamError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

function uploadErrorResponse(err: unknown): { status: number; message: string } {
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
  return { status, message };
}

// 识别要求至少一张照片，修正可以不带照片
function readImages(req: Request, required: boolean): UploadedImage[] {
  const files = Array.isArray(req.files) ? req.files : [];
  if ((required && files.length === 0) || files.some((file) => file.size === 0)) {
    throw new ClientInputError("图片无效或超过 8MB。");
  }
  const totalBytes = files.reduce((sum, file) => sum + file.size, 0);
  if (totalBytes > MAX_TOTAL_IMAGE_BYTES) {
    throw new ClientInputError("照片总大小超过 20MB。");
  }
  return files.map((file) => ({
    mimeType: file.mimetype,
    base64: uint8ArrayToBase64(file.buffer),
  }));
}

async function callModel(
  systemPrompt: string,
  userContent: unknown,
  requestId: string,
  maxTokens: number,
): Promise<{ content: string; provider: string; model: string }> {
  const provider = config.FOOD_AI_PROVIDER || "qwen";
  const providerConfig = resolveProvider(provider as "qwen" | "glm", config);

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
        { role: "system", content: systemPrompt },
        { role: "user", content: userContent },
      ],
      response_format: { type: "json_object" },
      enable_thinking: false,
      temperature: 0.1,
      max_completion_tokens: maxTokens,
    }),
  });

  if (!upstreamResponse.ok) {
    throw upstreamResponse.status === 429
      ? new UpstreamError(429, "模型服务繁忙，请稍后再试。")
      : new UpstreamError(502, "模型服务暂时不可用。");
  }

  const upstream = (await upstreamResponse.json()) as {
    choices?: Array<{ message?: { content?: string } }>;
  };
  const content = upstream.choices?.[0]?.message?.content;
  if (!content) {
    throw new UpstreamError(502, "模型没有返回可用结果。");
  }
  return { content, provider, model: providerConfig.model };
}

function sendError(
  res: Response,
  error: unknown,
  requestId: string,
  fallbackMessage: string,
) {
  if (error instanceof UpstreamError) {
    res.status(error.status).json({ message: error.message, requestId });
  } else if (error instanceof ClientInputError) {
    res.status(422).json({ message: error.message, requestId });
  } else {
    res.status(500).json({ message: fallbackMessage, requestId });
  }
}

// ---- 路由 ----

app.get("/health", (_req: Request, res: Response) => {
  res.json({
    status: "ok",
    promptVersion: PROMPT_VERSION,
    correctionPromptVersion: CORRECTION_PROMPT_VERSION,
    reviewPromptVersion: REVIEW_PROMPT_VERSION,
  });
});

app.post("/v1/food/analyze", (req: Request, res: Response) => {
  upload(req, res, async (err) => {
    const requestId =
      (req.headers["x-request-id"] as string) || randomUUID();

    if (err) {
      const { status, message } = uploadErrorResponse(err);
      res.status(status).json({ message, requestId });
      return;
    }

    try {
      const images = readImages(req, true);
      const context = cleanText(req.body?.userFoodContext, 500);
      const mealPeriod = cleanText(req.body?.mealPeriod, 20);
      const locale = cleanText(req.body?.locale, 30) || "zh-CN";

      const { content, provider, model } = await callModel(
        SYSTEM_PROMPT,
        buildUserContent(
          images,
          buildUserPrompt(context, mealPeriod, images.length, locale),
        ),
        requestId,
        2500,
      );

      const analysis = validateAnalysis(parseModelJSON(content));
      res.json({
        requestId,
        schemaVersion: 1,
        provider,
        model,
        promptVersion: PROMPT_VERSION,
        ...analysis,
      });
    } catch (error) {
      sendError(res, error, requestId, "食物识别服务暂时不可用。");
    }
  });
});

// 一句话修正：App 带上当前记录、之前的修正和本次说明，照片可选；只返回改动部分
app.post("/v1/food/correct", (req: Request, res: Response) => {
  upload(req, res, async (err) => {
    const requestId =
      (req.headers["x-request-id"] as string) || randomUUID();

    if (err) {
      const { status, message } = uploadErrorResponse(err);
      res.status(status).json({ message, requestId });
      return;
    }

    try {
      const instruction = cleanText(req.body?.instruction, MAX_CORRECTION_LENGTH);
      if (!instruction) {
        throw new ClientInputError("请说明需要修正的内容。");
      }
      const record = parseCorrectionRecord(req.body?.currentResult);
      const history = parseCorrectionHistory(req.body?.history);
      const images = readImages(req, false);
      const prompt = buildCorrectionUserPrompt({
        context: cleanText(req.body?.userFoodContext, 500),
        mealPeriod: cleanText(req.body?.mealPeriod, 20),
        imageCount: images.length,
        locale: cleanText(req.body?.locale, 30) || "zh-CN",
        record,
        history,
        instruction,
      });

      const { content, provider, model } = await callModel(
        CORRECTION_SYSTEM_PROMPT,
        images.length > 0 ? buildUserContent(images, prompt) : prompt,
        requestId,
        1500,
      );

      const correction = validateCorrection(
        parseModelJSON(content),
        record.items.length,
      );
      res.json({
        requestId,
        schemaVersion: 1,
        provider,
        model,
        promptVersion: CORRECTION_PROMPT_VERSION,
        ...correction,
      });
    } catch (error) {
      sendError(res, error, requestId, "修正服务暂时不可用。");
    }
  });
});

// 近期复盘：App 发来本地整理好的数据（payload 字段，JSON 字符串），不接受照片；数字由 App 填入
app.post("/v1/review/recent", (req: Request, res: Response) => {
  upload(req, res, async (err) => {
    const requestId =
      (req.headers["x-request-id"] as string) || randomUUID();

    if (err) {
      const { status, message } = uploadErrorResponse(err);
      res.status(status).json({ message, requestId });
      return;
    }

    try {
      if (readImages(req, false).length > 0) {
        throw new ClientInputError("复盘不需要照片。");
      }
      const payload = parseReviewPayload(req.body?.payload);
      const { content, provider, model } = await callModel(
        REVIEW_SYSTEM_PROMPT,
        buildReviewUserPrompt(payload),
        requestId,
        1200,
      );

      res.json({
        requestId,
        schemaVersion: 1,
        provider,
        model,
        promptVersion: REVIEW_PROMPT_VERSION,
        ...validateReview(parseModelJSON(content)),
      });
    } catch (error) {
      sendError(res, error, requestId, "复盘服务暂时不可用。");
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
