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
export const inject = ["webServer", "sessionProjectionCache", "sessions"];

/** 从投影快照里提取 token 用量桶 */
function usageBuckets(values) {
  const usage = values?.tokenUsage;
  if (!usage || typeof usage !== "object") return null;
  const buckets = usage.buckets ?? usage;
  if (typeof buckets !== "object") return null;
  return {
    inputTokens: Number(buckets.inputTokens ?? 0),
    uncachedInputTokens: Number(buckets.uncachedInputTokens ?? 0),
    outputTokens: Number(buckets.outputTokens ?? 0),
    cacheReadTokens: Number(buckets.cacheReadTokens ?? 0),
    cacheWriteTokens: Number(buckets.cacheWriteTokens ?? 0),
  };
}

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

  // Token 用量统计：有活跃会话返回该会话数据，否则返回今日所有会话聚合
  ctx.effect(() => ctx.webServer.register({
    kind: "exact",
    path: "/api/desktop/stats",
    handler: async (_req, res) => {
      const respond = (payload) => {
        res.writeHead(200, { "Content-Type": "application/json", "Cache-Control": "no-store" });
        res.end(JSON.stringify({ ok: true, ...payload }));
      };
      try {
        const sessions = ctx.sessions?.list?.() ?? [];
        // 最近活跃的 attached 会话
        const active = sessions
          .map((s) => ({ id: s.id, updated: s.updatedAt ?? s.header?.updatedAt ?? 0 }))
          .sort((a, b) => String(b.updated).localeCompare(String(a.updated)))[0];
        if (active && ctx.sessionProjectionCache) {
          const snap = await ctx.sessionProjectionCache.coldSnapshot(active.id);
          const usage = usageBuckets(snap?.values);
          if (usage) {
            return respond({ scope: "当前会话", usage, sessionId: active.id });
          }
        }
        // 无活跃会话/数据：今日聚合（遍历持久化缓存）
        const usage = await todayAggregate(ctx);
        if (usage) return respond({ scope: "今日总计", usage });
        return respond({ scope: "暂无数据", usage: null });
      } catch (error) {
        res.writeHead(500, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ ok: false, error: error.message }));
      }
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

/** 今日聚合：遍历持久化投影缓存里今天的会话（字段细节见 .research/dsh-protocol.md） */
async function todayAggregate(ctx) {
  // 占位实现：仅聚合 attached 会话；持久化全量扫描待协议文档确认后补全
  const sessions = ctx.sessions?.list?.() ?? [];
  const buckets = { inputTokens: 0, uncachedInputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0 };
  let found = false;
  for (const s of sessions) {
    if (!ctx.sessionProjectionCache) continue;
    try {
      const snap = await ctx.sessionProjectionCache.coldSnapshot(s.id);
      const usage = usageBuckets(snap?.values);
      if (!usage) continue;
      found = true;
      for (const k of Object.keys(buckets)) buckets[k] += usage[k];
    } catch {
      // 单个会话读取失败不影响聚合
    }
  }
  return found ? buckets : null;
}
