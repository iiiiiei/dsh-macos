/**
 * dsh-desktop-bridge — DSH 桌面桥接插件（宿主侧）
 *
 * 让 DSH 生态里的任何插件都能与 macOS 桌面应用通信：
 *   GET  /api/desktop/status   服务器状态（pid、版本、运行时长）
 *   POST /api/desktop/notify   通过 osascript 触发 macOS 原生通知
 *
 * 这是"桌面集成即插件"的示例：桌面应用只是 DSH 插件生态的一个普通消费者，
 * 与工具卡片、子代理面板等 UI 插件处于同一条 Cordis 插件流水线上。
 */
import { execFile } from "node:child_process";

export const name = "dsh-desktop-bridge";
export const inject = ["webServer"];

export function apply(ctx) {
  const startedAt = Date.now();

  // 服务器状态：供桌面应用健康检查 / 状态栏展示
  // 注意：ctx.effect(callback) 会立即执行 callback 并把其返回值当作
  // disposer 保存，因此必须把 register 调用包在箭头函数里返回。
  ctx.effect(() => ctx.webServer.register({
    kind: "exact",
    path: "/api/desktop/status",
    handler: async (_req, res) => {
      res.writeHead(200, {
        "Content-Type": "application/json",
        "Cache-Control": "no-store",
      });
      res.end(JSON.stringify({
        ok: true,
        pid: process.pid,
        uptimeMs: Date.now() - startedAt,
        version: process.env.npm_package_version ?? "unknown",
        profile: process.env.DSH_PROFILE ?? "web",
      }));
    },
  }));

  // 原生通知：通过 osascript 触发（无需额外权限）
  ctx.effect(() => ctx.webServer.register({
    kind: "exact",
    path: "/api/desktop/notify",
    handler: async (req, res) => {
      let body = "";
      for await (const chunk of req) body += chunk;
      let payload = {};
      try {
        payload = JSON.parse(body || "{}");
      } catch {
        // 忽略非法 JSON，走默认文案
      }
      const title = String(payload.title ?? "DSH Desktop");
      const message = String(payload.message ?? "");
      const script = `display notification ${JSON.stringify(message)} with title ${JSON.stringify(title)}`;
      execFile("/usr/bin/osascript", ["-e", script], (error) => {
        res.writeHead(error ? 500 : 200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ ok: !error, error: error ? error.message : null }));
      });
    },
  }));

  ctx.logger.info("dsh-desktop-bridge: /api/desktop/status + /api/desktop/notify ready");
}
