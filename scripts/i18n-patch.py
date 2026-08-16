#!/usr/bin/env python3
"""DSH 官方 i18n 遗漏汉化补丁（硬编码 UI 文本）
用法: python3 i18n-patch.py   （修改 npx 缓存，幂等；DSH 升级后需重跑；重启 DSH 生效）
"""
import re, os, sys

NPX = "/Users/iiiiiei/.npm/_npx/"
patched = 0

def patch_file(pkg, subs, mode="attr"):
    """mode=attr: 只替换 'prop: "值"' 形式；mode=desc: 只替换 description: "值" 形式"""
    global patched
    for d in sorted(os.listdir(NPX)):
        f = os.path.join(NPX, d, "node_modules", "@deepseek-ai", pkg, "lib", "client.js")
        if not os.path.exists(f):
            continue
        s = open(f, encoding="utf-8").read()
        orig = s
        for old, new in subs:
            if mode == "attr":
                s = re.sub(r'((?:children|label|title|placeholder|aria-label|description|tooltip|text)\s*:\s*)"' + re.escape(old) + r'"',
                           r'\1"' + new + '"', s)
            else:
                s = re.sub(r'(description\s*:\s*)"' + re.escape(old) + r'"',
                           r'\1"' + new + '"', s)
        if s != orig:
            open(f, "w", encoding="utf-8").write(s)
            print(f"已汉化: {pkg} ({len(subs)} 条)")
            patched += 1
        return
    print(f"跳过（未找到）: {pkg}")

# 1) 轨迹面板（对话窗口的轨迹视图）
trajectory = [
    ("Assistant Message", "助手消息"), ("CONTEXT", "上下文"), ("Cache created", "缓存已创建"),
    ("Cached", "已缓存"), ("Compaction", "压缩"), ("Content", "内容"),
    ("Drag to resize. Double-click to reset.", "拖动调整大小，双击重置"),
    ("Duration", "耗时"), ("Generation", "生成"), ("Message", "消息"),
    ("Message source JSON", "消息源 JSON"), ("No system prompt in this request", "此请求无系统提示词"),
    ("No timing data", "无耗时数据"), ("No tools in this request", "此请求无工具调用"),
    ("Not available", "不可用"), ("Open image", "打开图片"), ("Open tool call summary", "打开工具调用摘要"),
    ("Options", "选项"), ("Options not recorded", "未记录选项"), ("Output", "输出"),
    ("Parameters", "参数"), ("Payload", "载荷"), ("Preview", "预览"), ("Provider", "提供方"),
    ("Purpose", "用途"), ("Raw Output", "原始输出"), ("Reasoning", "推理"),
    ("Request Timing", "请求耗时"), ("Request options JSON", "请求选项 JSON"),
    ("Result", "结果"), ("Result JSON", "结果 JSON"), ("Retry delay", "重试延迟"),
    ("SYSTEM", "系统"), ("Schema", "结构"), ("Schema unavailable", "结构不可用"),
    ("Session cumulative", "会话累计"), ("Source", "来源"), ("Source not recorded", "未记录来源"),
    ("Started", "开始于"), ("Status", "状态"), ("Subtool calls", "子工具调用"),
    ("Summary", "摘要"), ("System Prompt", "系统提示词"), ("This request", "本次请求"),
    ("Throughput", "吞吐"), ("Timing", "耗时"), ("Timing source", "耗时来源"),
    ("Tool Call", "工具调用"), ("Tool calls", "工具调用"), ("Total duration", "总耗时"),
    ("Usage not reported", "未上报用量"),
]
patch_file("dsh-client-ui-trajectory", trajectory, mode="attr")

# 2) 斜杠命令描述（对话窗口输入框的 /命令列表）
commands = [
    ("Enter or leave plan mode", "进入或退出计划模式"),
    ("List notes", "列出笔记"),
    ("Read the notes files and summarize", "阅读笔记文件并总结"),
    ("Writing a harness plugin", "编写 harness 插件"),
    ("set or view the goal for a long-running task", "设置或查看长期任务的目标"),
]
patch_file("dsh-client-connection", commands, mode="desc")

# 3) Session log 按钮 + 权限选项（早期补丁，保持幂等）
for d in sorted(os.listdir(NPX)):
    f1 = os.path.join(NPX, d, "node_modules", "@deepseek-ai", "dsh-session-log-export", "lib", "client.js")
    if os.path.exists(f1):
        s = open(f1, encoding="utf-8").read()
        if '"Session log"' in s:
            s = re.sub(r'(children\s*:\s*)"Session log"', r'\1"会话日志"', s)
            open(f1, "w", encoding="utf-8").write(s)
            print("已汉化: dsh-session-log-export (Session log -> 会话日志)")
            patched += 1
    f2 = os.path.join(NPX, d, "node_modules", "@deepseek-ai", "dsh-client-ui-permission-presets", "lib", "client.js")
    if os.path.exists(f2):
        s = open(f2, encoding="utf-8").read()
        if '"Full access"' in s:
            s = s.replace('value === "danger-full-access" ? "Full access" : displayPresetName(name)',
                          'value === "danger-full-access" ? "完全访问" : displayPresetName(name)')
            s = s.replace('"启用 Full access"', '"启用完全访问"').replace('"确认启用 Full access？"', '"确认启用完全访问？"')
            open(f2, "w", encoding="utf-8").write(s)
            print("已汉化: dsh-client-ui-permission-presets (Full access -> 完全访问)")
            patched += 1

if patched == 0:
    print("没有需要汉化的文件（可能已全部汉化或包已更新）")
    sys.exit(1)
print("汉化补丁完成，重启 DSH 服务器后生效。")
