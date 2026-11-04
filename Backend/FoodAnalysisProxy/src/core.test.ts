// 复盘模型配置的测试：npm test
import { test } from "node:test";
import assert from "node:assert/strict";

import {
  CORRECTION_PROMPT_VERSION,
  PROMPT_VERSION,
  REVIEW_PROMPT_VERSION,
  buildHealthPayload,
  resolveFoodModel,
  resolveProvider,
  resolveReviewModel,
  type CoreConfig,
} from "./core";

const base: CoreConfig = {
  FOOD_AI_PROVIDER: "qwen",
  FOOD_AI_MODEL: "qwen3.7-plus",
  QWEN_API_KEY: "sk-test",
};

test("不设置 REVIEW_AI_MODEL 时，复盘沿用 FOOD_AI_MODEL", () => {
  assert.equal(resolveFoodModel("qwen", base), "qwen3.7-plus");
  assert.equal(resolveReviewModel("qwen", base), "qwen3.7-plus");
  assert.equal(resolveProvider("qwen", base).model, "qwen3.7-plus");
});

test("REVIEW_AI_MODEL 为空字符串时同样回退到 FOOD_AI_MODEL", () => {
  const config = { ...base, REVIEW_AI_MODEL: "" };
  assert.equal(resolveReviewModel("qwen", config), "qwen3.7-plus");
});

test("设置 REVIEW_AI_MODEL 后只影响复盘，识别与修正不变", () => {
  const config = { ...base, REVIEW_AI_MODEL: "qwen3.8-max" };
  assert.equal(resolveReviewModel("qwen", config), "qwen3.8-max");
  assert.equal(resolveFoodModel("qwen", config), "qwen3.7-plus");
  assert.equal(resolveProvider("qwen", config).model, "qwen3.7-plus");
});

test("两个变量都不设置时使用原来的默认模型", () => {
  assert.equal(resolveReviewModel("qwen", { QWEN_API_KEY: "sk" }), "qwen3.7-plus");
  assert.equal(resolveProvider("qwen", { QWEN_API_KEY: "sk" }).model, "qwen3.7-plus");
  assert.equal(resolveReviewModel("glm", { GLM_API_KEY: "k" }), "glm-4.6v-flash");
  assert.equal(resolveProvider("glm", { GLM_API_KEY: "k" }).model, "glm-4.6v-flash");
});

test("/health 返回复盘模型，原有字段不变", () => {
  assert.deepEqual(buildHealthPayload(base), {
    status: "ok",
    promptVersion: PROMPT_VERSION,
    correctionPromptVersion: CORRECTION_PROMPT_VERSION,
    reviewPromptVersion: REVIEW_PROMPT_VERSION,
    reviewModel: "qwen3.7-plus",
  });
  assert.equal(
    buildHealthPayload({ ...base, REVIEW_AI_MODEL: "qwen3.8-max" }).reviewModel,
    "qwen3.8-max",
  );
});

test("/health 不需要 API Key", () => {
  assert.equal(buildHealthPayload({}).reviewModel, "qwen3.7-plus");
});
