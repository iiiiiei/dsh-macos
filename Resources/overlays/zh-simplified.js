/**
 * dsh-macos Appearance Overlay — zh-simplified（中文通俗说明）
 *
 * 原则（与工程任务单一致）：
 *  - Overlay Only：不改官方源码，仅注入本脚本；可整体关闭并还原官方原文。
 *  - 只翻译固定 UI 标签（Sidebar / Toolbar / 轨迹面板 / 斜杠命令描述 / 设置面板固定标签）。
 *  - 聊天正文保护：仅做"整节点精确匹配"（文本节点内容 === 映射键），
 *    用户消息 / 助手流式输出 / 代码块等句子不会命中映射，天然不受影响。
 *  - 低内存：固定 UI 初始化翻译一次；动态容器只观察新增节点子树，
 *    绝不在 Mutation 回调里做全量扫描，不观察 document.body 的 subtree。
 */
(function () {
  if (window.__dshZhOverlay) return;

  var MANIFEST = {
    id: "zh-simplified",
    name: "中文通俗说明",
    version: "1.0.0",
    compatibleOfficialHint: "0.1.0-rc.6",
    officialVersion: "0.1.0-rc.6",
    createdAt: "2026-08-16",
  };

  // 固定 UI 标签映射（键为官方原文，整节点匹配）
  var MAP = {
    "Session log": "会话日志",
    "Assistant Message": "助手消息",
    "ASSISTANT": "助手",
    "CONTEXT": "上下文",
    "Cache created": "缓存已创建",
    "Cached": "已缓存",
    "Compaction": "压缩",
    "Content": "内容",
    "Drag to resize. Double-click to reset.": "拖动调整大小，双击重置",
    "Duration": "耗时",
    "Generation": "生成",
    "Message": "消息",
    "Message source JSON": "消息源 JSON",
    "No system prompt in this request": "此请求无系统提示词",
    "No timing data": "无耗时数据",
    "No tools in this request": "此请求无工具调用",
    "Not available": "不可用",
    "Open image": "打开图片",
    "Open tool call summary": "打开工具调用摘要",
    "Options": "选项",
    "Options not recorded": "未记录选项",
    "Output": "输出",
    "Parameters": "参数",
    "Payload": "载荷",
    "Preview": "预览",
    "Provider": "提供方",
    "Purpose": "用途",
    "Raw Output": "原始输出",
    "Reasoning": "推理",
    "Request Timing": "请求耗时",
    "Request options JSON": "请求选项 JSON",
    "Result": "结果",
    "Result JSON": "结果 JSON",
    "Retry delay": "重试延迟",
    "SYSTEM": "系统",
    "Schema": "结构",
    "Schema unavailable": "结构不可用",
    "Session cumulative": "会话累计",
    "Source": "来源",
    "Source not recorded": "未记录来源",
    "Started": "开始于",
    "Status": "状态",
    "Subtool calls": "子工具调用",
    "Summary": "摘要",
    "System Prompt": "系统提示词",
    "This request": "本次请求",
    "Throughput": "吞吐",
    "Timing": "耗时",
    "Timing source": "耗时来源",
    "Tool Call": "工具调用",
    "Tool calls": "工具调用",
    "Total duration": "总耗时",
    "Usage not reported": "未上报用量",
    "Full access": "完全访问",
    "Enter or leave plan mode": "进入或退出计划模式",
    "List notes": "列出笔记",
    "Read the notes files and summarize": "阅读笔记文件并总结",
    "Writing a harness plugin": "编写 harness 插件",
    "set or view the goal for a long-running task": "设置或查看长期任务的目标",
    "Enable Full access?": "确认启用完全访问？",
    "Full access lets new sessions reduce confirmation steps and perform more actions directly, including sensitive operations, file changes, or external commands. Only use it when you trust subsequent tasks.": "启用完全访问后，新会话将减少确认步骤，并且可以直接执行更多操作，包括敏感操作、文件修改或外部命令。仅建议在你信任后续任务时使用。",
    "Full access reduces confirmation steps and lets the agent perform more actions directly, including sensitive operations, file changes, or external commands. Only use it when you trust the current task.": "启用完全访问后，agent 将减少确认步骤，并且可以直接执行更多操作，包括敏感操作、文件修改或外部命令。仅建议在你信任当前任务时使用。",
    "I understand the risks and want to continue": "我已了解风险，并愿意继续",
    "Enable Full access": "启用完全访问",
    "Cancel": "取消",
    "Choose the default permission mode for new sessions": "选择新会话的默认权限模式",
    "Loading": "加载中",
    "Unavailable": "不可用",
    "Agent preset": "智能体预设",
    "Applies to sessions you start from now on. Running sessions keep the preset they began with.": "适用于之后启动的会话；运行中的会话保持其初始预设。",
    "English": "English",
  };

  var translated = []; // {node, orig} 用于关闭时还原（Fully Reversible）

  /** 翻译单个文本节点：整节点精确匹配，未命中保持原文 */
  function translateTextNode(node) {
    if (node.nodeType !== 3) return false;
    var text = node.data;
    var trimmed = text.trim();
    if (!trimmed) return false;
    var hit = MAP[trimmed];
    if (hit === undefined || hit === text) return false;
    node.data = text.replace(trimmed, hit);
    translated.push({ node: node, orig: text });
    return true;
  }

  /** 遍历容器内文本节点（TreeWalker，非 querySelectorAll("*")） */
  function walk(container) {
    var walker = document.createTreeWalker(container, NodeFilter.SHOW_TEXT);
    var n;
    var count = 0;
    while ((n = walker.nextNode())) {
      if (translateTextNode(n)) count++;
    }
    return count;
  }

  /** 固定 UI：初始化翻译一次（幂等：已翻译节点不再命中映射） */
  function translateFixedUI() {
    if (!document.body) return;
    walk(document.body);
    registerDynamicContainers();
  }

  // 动态容器（Dialog / Popover / Menu / Tooltip / Permission / Tool 面板）：
  // 只观察 body 直接子级的新增（React portal 挂载点），对新增容器只处理其自身子树；
  // 不观察 body subtree，不做全量持续翻译；初始化仅一次枚举既有弹层容器。
  var dynamicObserver = null;

  function registerDynamicContainers() {
    if (dynamicObserver) return;
    dynamicObserver = new MutationObserver(function (mutations) {
      for (var i = 0; i < mutations.length; i++) {
        var added = mutations[i].addedNodes;
        for (var j = 0; j < added.length; j++) {
          var node = added[j];
          if (node.nodeType !== 1) continue;
          if (isDynamicContainer(node)) {
            walk(node);
            observeContainer(node);
          }
        }
      }
    });
    // childList-only：仅捕获新增顶层容器，不扫描既有子树
    dynamicObserver.observe(document.body, { childList: true });
    // 已存在的动态容器也要覆盖（初始化时一次）
    var existing = document.querySelectorAll('[role="dialog"], [role="menu"], [role="tooltip"], [role="listbox"], [role="alertdialog"], [class*="popover"], [class*="panel"], [class*="dialog"]');
    for (var k = 0; k < existing.length; k++) {
      walk(existing[k]);
      observeContainer(existing[k]);
    }
  }

  function isDynamicContainer(el) {
    var role = el.getAttribute && el.getAttribute("role");
    var cls = el.className && String(el.className);
    return (role === "dialog" || role === "menu" || role === "tooltip" || role === "listbox" || role === "alertdialog")
      || (cls && (/popover|panel|dialog/i.test(cls)));
  }

  var containerObserver = new MutationObserver(function (mutations) {
    for (var i = 0; i < mutations.length; i++) {
      var added = mutations[i].addedNodes;
      for (var j = 0; j < added.length; j++) {
        if (added[j].nodeType === 1) walk(added[j]);
      }
    }
  });

  function observeContainer(el) {
    try { containerObserver.observe(el, { childList: true, subtree: true }); } catch (e) {}
  }

  /** 开关（Fully Reversible）：关闭时还原全部已翻译节点为官方原文 */
  function setEnabled(enabled) {
    if (enabled) {
      if (dynamicObserver) dynamicObserver.disconnect();
      dynamicObserver = null;
      if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", translateFixedUI, { once: true });
      } else {
        translateFixedUI();
      }
    } else {
      if (dynamicObserver) { dynamicObserver.disconnect(); dynamicObserver = null; }
      containerObserver.disconnect();
      for (var i = 0; i < translated.length; i++) {
        var rec = translated[i];
        if (rec.node && rec.node.isConnected !== false) rec.node.data = rec.orig;
      }
      translated = [];
    }
  }

  window.__dshZhOverlay = {
    manifest: MANIFEST,
    setEnabled: setEnabled,
    get enabled() {
      return dynamicObserver !== null || translated.length > 0;
    },
  };

  // 默认启用（应用侧会按用户设置再校准一次）
  setEnabled(true);
})();
