/**
 * dsh-macos Appearance Overlay — desktop-layout（方案1 Desktop 布局对齐）
 *
 * 只影响显示（spacing/margin/width），不改 DOM 结构、不劫持事件。
 * 幂等：style 元素以固定 id 注入，重复执行不重复添加。
 * 选择器为 DSH 0.1.0-rc.6 构建的 hashed class（内容哈希，同版本稳定），
 * 升级官方包后需按 manifest.compatibleOfficialHint 重新校准。
 *
 * 对齐目标（方案1）：
 *  - 展开态 logo 行在红绿灯下方（--dsh-traffic-inset 由原生动态注入）
 *  - 折叠态侧栏 56px → 90px（官方 56px 轨在其中随布局居中）
 */
(function () {
  if (document.getElementById("dsh-desktop-layout")) return;
  var style = document.createElement("style");
  style.id = "dsh-desktop-layout";
  style.textContent = [
    // 展开态：logo 行从红绿灯行下方开始（原生注入红绿灯行高）
    ".hHd-Xa_logoRow { margin-top: var(--dsh-traffic-inset, 28px) !important; }",
    // 折叠态：侧栏宽度适配红绿灯在折叠侧栏内水平居中（以红绿灯系统默认
    // 绝对位置为锚）：宽 = 红绿灯左缘 × 2 + 组宽。注入的 --dsh-traffic-width
    // 含 8px 尾部间距，故减去；实测左缘 7 + 组宽 54 → 68px
    ".pI_x6G_sidebarCol:has(.hHd-Xa_collapsed) { width: calc(var(--dsh-traffic-left) * 2 + var(--dsh-traffic-width) - 8px) !important; }",
    // 折叠态：去掉 railIn 左右 10px 内缩，图标列右缘与侧栏右缘合一（视觉连贯），
    // 红绿灯组（左缘 7 ~ 右缘 61）在侧栏 68px 内严格居中（左 7 / 右 7）
    ".pI_x6G_sidebarCol:has(.hHd-Xa_collapsed) .hHd-Xa_railIn { padding-left: 0 !important; padding-right: 0 !important; }",
    // 主内容区让出透明标题栏行：padding = 拖拽带行高 - 顶栏固有间距 12px，
    // 使顶栏最高元素（session log 按钮）上边框贴紧拖拽带下限
    ".pI_x6P_centerCol, .pI_x6G_centerCol { padding-top: calc(var(--dsh-traffic-inset, 28px) - 12px) !important; }",
    // 会话选中框/悬停框：弹性宽度（随侧栏宽变化）+ 水平居中，
    // 左右边距 = 新会话按钮边距 20px（按钮 216 在 logoRow 256 内居中）。
    // 源码依据：.YDXeBa_sessionRow 无左右 margin（高亮框贴满内容区 256px），
    // 与按钮 216px 宽度不一致，这里用边距对齐按钮
    // 选中框父级(_root_1b2ny_3)右缘 276 比 logoRow 右缘 268 宽 8px（DSH 布局差异），
    // 右 margin 28 = 20 + 8 补偿，使选中框与按钮同宽(216)同右缘(248)、
    // 中心(140)与按钮/侧栏中心一致；宽度仍随侧栏弹性变化
    ".YDXeBa_sessionRow { box-sizing: border-box !important; width: calc(100% - 48px) !important; margin-left: 20px !important; margin-right: 28px !important; }",
    // 折叠态设置图标在底部区域内垂直居中
    ".hHd-Xa_settingsArea { display: flex !important; align-items: center !important; justify-content: center !important; }",
  ].join("\n");
  document.head.appendChild(style);
})();
