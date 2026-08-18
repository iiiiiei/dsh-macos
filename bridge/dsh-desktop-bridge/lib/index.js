/**
 * dsh-desktop-bridge — DSH 桌面桥接插件（宿主侧）
 *
 * 让 DSH 生态里的任何插件都能与 macOS 桌面应用通信：
 *   GET  /api/desktop/status   服务器状态（pid、版本、运行时长）
 *
 * 这是"桌面集成即插件"的示例：桌面应用只是 DSH 插件生态的一个普通消费者，
 * 与工具卡片、子代理面板等 UI 插件处于同一条 Cordis 插件流水线上。
 */

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


  ctx.logger.info("dsh-desktop-bridge: /api/desktop/status ready");
}

