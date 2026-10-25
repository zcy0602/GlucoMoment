import {
  CoreConfig,
  ClientInputError,
  PROMPT_VERSION,
  MAX_IMAGE_BYTES,
  MAX_IMAGE_COUNT,
  SYSTEM_PROMPT,
  resolveProvider,
  buildUserPrompt,
  buildUserContent,
  cleanText,
  parseModelJSON,
  validateAnalysis,
  uint8ArrayToBase64,
} from "./core";

interface RateLimiter {
  limit(input: { key: string }): Promise<{ success: boolean }>;
}

interface Env extends CoreConfig {
  RATE_LIMITER?: RateLimiter;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/health") {
      return json({ status: "ok", promptVersion: PROMPT_VERSION });
    }
    if (request.method !== "POST" || url.pathname !== "/v1/food/analyze") {
      return json({ message: "Not found" }, 404);
    }

    const requestId =
      request.headers.get("X-Request-Id") || crypto.randomUUID();
    const installId =
      request.headers.get("X-Install-Id") || "anonymous";

    if (env.RATE_LIMITER) {
      const rateLimit = await env.RATE_LIMITER.limit({ key: installId });
      if (!rateLimit.success) {
        return json(
          { message: "请求过于频繁，请稍后再试。", requestId },
          429,
        );
      }
    }

    try {
      const form = await request.formData();
      const images = form.getAll("image");
      if (images.length > MAX_IMAGE_COUNT) {
        return json(
          { message: `一次最多上传 ${MAX_IMAGE_COUNT} 张照片。`, requestId },
          422,
        );
      }
      const files: File[] = [];
      for (const image of images) {
        if (
          !(image instanceof File) ||
          image.size === 0 ||
          image.size > MAX_IMAGE_BYTES
        ) {
          return json({ message: "图片无效或超过 8MB。", requestId }, 422);
        }
        if (!image.type.startsWith("image/")) {
          return json({ message: "仅支持图片文件。", requestId }, 415);
        }
        files.push(image);
      }
      if (files.length === 0) {
        return json({ message: "图片无效或超过 8MB。", requestId }, 422);
      }

      const context = cleanText(form.get("userFoodContext"), 500);
      const mealPeriod = cleanText(form.get("mealPeriod"), 20);
      const locale = cleanText(form.get("locale"), 30) || "zh-CN";
      const provider = env.FOOD_AI_PROVIDER || "qwen";
      const providerConfig = resolveProvider(
        provider as "qwen" | "glm",
        env as CoreConfig,
      );
      const uploadedImages = await Promise.all(
        files.map(async (file) => ({
          mimeType: file.type,
          base64: uint8ArrayToBase64(new Uint8Array(await file.arrayBuffer())),
        })),
      );

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
        return json(
          {
            message:
              upstreamResponse.status === 429
                ? "模型服务繁忙，请稍后再试。"
                : "模型服务暂时不可用。",
            requestId,
          },
          upstreamResponse.status === 429 ? 429 : 502,
        );
      }

      const upstream = (await upstreamResponse.json()) as {
        choices?: Array<{ message?: { content?: string } }>;
      };
      const content = upstream.choices?.[0]?.message?.content;
      if (!content) {
        return json(
          { message: "模型没有返回可用结果。", requestId },
          502,
        );
      }

      const analysis = validateAnalysis(parseModelJSON(content));
      return json({
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
      return json(
        { message, requestId },
        error instanceof ClientInputError ? 422 : 500,
      );
    }
  },
};

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
}
