# Food Analysis Proxy

无状态的餐食图片分析代理。它负责保护供应商密钥、限制请求频率、维护提示词并校验模型 JSON；不会保存图片、用户描述或餐食记录。

## 本地配置

1. 将 `wrangler.jsonc.example` 复制为 `wrangler.jsonc`。
2. 根据需要设置 `FOOD_AI_PROVIDER`、`FOOD_AI_MODEL` 和 `AI_BASE_URL`。
   示例配置默认使用支持图像输入的 `qwen3.7-plus`。
3. 只在 Secret 中保存供应商密钥：

```bash
npx wrangler secret put QWEN_API_KEY
# 或
npx wrangler secret put GLM_API_KEY
```

不要把 `.dev.vars`、`.env`、`wrangler.jsonc` 或 API Key 提交到 Git。

## 运行

```bash
npm install
npm run typecheck
npm run dev
```

部署：

```bash
npm run deploy
```

部署完成后，把 Xcode Build Setting 中的 `GMFoodAnalysisEndpoint` 设置为：

```text
https://你的域名/v1/food/analyze
```

如果该值为空，iOS App 会自动使用与真实接口相同结构的本地 Demo 服务，便于离线开发和 UI 测试。

## 接口

- `GET /health`：健康检查，不调用模型。
- `POST /v1/food/analyze`：`multipart/form-data`，图片字段名为 `image`。

代理只记录平台自身的请求元数据。不要在日志中输出表单内容、图片 Base64、模型完整请求或响应。
