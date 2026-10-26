# Food Analysis Proxy

无状态的餐食图片分析代理。它负责保护供应商密钥、限制请求频率、维护提示词并校验模型 JSON；不会保存图片、用户描述或餐食记录。

## 接口

- `GET /health`：健康检查，不调用模型。
- `POST /v1/food/analyze`：`multipart/form-data`，图片字段名为 `image`，可重复 1～6 次，按顺序作为同一餐的多张照片。
- `POST /v1/food/correct`：一句话修正，`multipart/form-data`。字段 `instruction`（本次说明，最多 200 字）、`currentResult`（当前记录 JSON，含用户手动修改）、`history`（之前的修正 JSON 数组，最多取最近 10 轮），以及 `userFoodContext`、`mealPeriod`、`locale`；`image` 可选，0～6 张。代理同样不保存会话，返回 `reply`、`updatedItems`（带 `ref`）、`addedItems`、`removedRefs`、`followUpQuestions`，由 App 合并到当前记录。地址由识别地址末尾的 `analyze` 换成 `correct` 得到。
- `POST /v1/review/recent`：近期复盘，`multipart/form-data`，不接受照片。字段 `payload` 是 App 在本地整理好的 JSON（每餐的餐后指标、曲线和分组比较，最大 64KB），代理只检查结构，然后原样交给模型。返回最多 3 条 `items`，每条包含 `text`、`mealIds`、`comparisonIds`、`guidelineId`。`text` 里的数字是 `{M1.peakRise}` 这样的占位符，由 App 校验后填入本地数值。地址由识别地址末尾的 `food/analyze` 换成 `review/recent` 得到。

代理只记录平台自身的请求元数据。不要在日志中输出表单内容、图片 Base64、模型完整请求或响应。不要把 `.env` 或 API Key 提交到 Git。

---

## Windows Server（Node.js）部署

### 环境要求

- **Node.js 22 LTS**（[nodejs.org](https://nodejs.org/) 下载 `.msi` 安装包）
- 能访问阿里云 DashScope API（`dashscope.aliyuncs.com`）

### 1. 安装依赖与编译

```powershell
cd FoodAnalysisProxy
npm install
npm run build:server
```

编译产物输出到 `dist/` 目录。

### 2. 配置环境变量

将 `.env.example` 复制为 `.env`，填入实际值：

```powershell
copy .env.example .env
```

编辑 `.env`：

```bash
PORT=8787
FOOD_AI_PROVIDER=qwen
FOOD_AI_MODEL=qwen3.7-plus
AI_BASE_URL=https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions
QWEN_API_KEY=你的阿里云API-Key
```

### 3. 验证

```powershell
node dist/server.js
```

确认输出 `稳糖食刻食物识别代理已启动 → http://localhost:8787`。

健康检查：

```powershell
curl http://localhost:8787/health
# → {"status":"ok","promptVersion":"food-analysis-v2"}
```

### 4. 注册 Windows Service（开机自启 + 崩溃重启）

使用 [nssm](https://nssm.cc/)（Non-Sucking Service Manager）：

```powershell
# 下载 nssm.exe（约 500KB），放到 C:\nssm\ 或 PATH 目录
# https://nssm.cc/download

nssm install GlucoMomentProxy
```

在弹出的 GUI 中设置：
- **Application path**：`C:\Program Files\nodejs\node.exe`
- **Startup directory**：`C:\你的路径\FoodAnalysisProxy`
- **Arguments**：`dist/server.js`

也可以用命令行：

```powershell
nssm install GlucoMomentProxy "C:\Program Files\nodejs\node.exe" "dist/server.js"
nssm set GlucoMomentProxy AppDirectory "C:\你的路径\FoodAnalysisProxy"
nssm set GlucoMomentProxy Start SERVICE_AUTO_START
nssm start GlucoMomentProxy
```

### 5. 配置 HTTPS（可选）

在 Windows Server 上安装 Nginx，配置反向代理 + Let's Encrypt（certbot 或 win-acme）：

```nginx
server {
    listen 443 ssl;
    server_name 你的域名;

    ssl_certificate     /path/to/fullchain.pem;
    ssl_certificate_key /path/to/privkey.pem;

    location /v1/food/analyze {
        proxy_pass http://127.0.0.1:8787;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        client_max_body_size 25m;
    }

    location /health {
        proxy_pass http://127.0.0.1:8787;
    }
}
```

### 6. 更新 App 设置

在 iOS App 的"AI 食物识别"设置中，选择"自建代理"，可以填入服务器根地址：

```text
http://你的服务器IP:8787/
```

App 会自动补全 `/v1/food/analyze`。也可以直接填写完整地址：

```text
https://你的域名/v1/food/analyze
```

---

## 开发

```bash
# 本地运行（读取 .env）
npm run dev:server

# 类型检查
npm run typecheck
```

## 代码结构

```
src/
├── core.ts     # 提示词、模型调用与输出校验
└── server.ts   # Node.js Express 入口
```
