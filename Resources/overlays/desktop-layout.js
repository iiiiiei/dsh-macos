/**
 * dsh-macos local desktop-shell layout.
 *
 * 规则（与原生外壳约定一致）：
 * 1. 红绿灯中心锚点 (23, 23)，灯组整体平移，不改按钮相对位置。
 * 2. 折叠侧栏宽 86px：红绿灯组中心 x=43 位于侧栏水平中心。
 * 3. 官方 56px 轨在 86px 侧栏内居中。
 * 4. 侧栏内容顶部偏移 32px：使 logo 行下边界对齐右侧会话顶栏下边界。
 */
(function () {
  if (document.getElementById("dsh-desktop-layout")) return;

  var style = document.createElement("style");
  style.id = "dsh-desktop-layout";
  style.textContent = [
    "html, body, #root { width: 100%; height: 100%; }",
    "body { margin: 0 !important; }",

    // 根 frame 只负责外层列布局，不干预官方内部网格。
    ".pI_x6G_frame { box-sizing: border-box !important; }",

    // 侧栏分隔线从窗口顶贯穿到底，包括透明标题栏区域。
    ".pI_x6G_sidebarCol { border-right: 1px solid color-mix(in srgb, currentColor 14%, transparent) !important; box-sizing: border-box !important; }",

    // 展开态：logo 行下边界对齐右侧会话顶栏下边界。
    ".pI_x6G_sidebarCol:not(:has(.hHd-Xa_collapsed)) .hHd-Xa_root { padding-top: 32px !important; box-sizing: border-box !important; }",
    // 折叠态：鲸鱼 logo 下边界同样对齐会话顶栏下边界（鲸鱼图标高度更小，需更大 padding-top）。
    ".pI_x6G_sidebarCol:has(.hHd-Xa_collapsed) .hHd-Xa_root { padding-top: 42px !important; box-sizing: border-box !important; }",

    // 折叠态：86px 外壳列，56px 官方轨居中。
    ".pI_x6G_frame:has(.hHd-Xa_collapsed) { grid-template-columns: 86px minmax(0, 1fr) 0px !important; }",
    ".pI_x6G_sidebarCol:has(.hHd-Xa_collapsed) .hHd-Xa_root { width: 56px !important; margin-left: auto !important; margin-right: auto !important; }",

    // 折叠轨图标居中，不改原生图标尺寸。
    ".pI_x6G_sidebarCol:has(.hHd-Xa_collapsed) .qDHVXG_root { align-items: center !important; }",
    // 会话/项目行（选中框/悬停框）与“新会话”按钮同宽同缘，避免右侧突出。
    // 使用属性选择器，兼容官方 Web UI 类名哈希变化。
    "[class*=\"sessionRow\"], [class*=\"projectRow\"] { box-sizing: border-box !important; width: calc(100% - 32px) !important; margin-left: 16px !important; margin-right: 16px !important; }",

    ".hHd-Xa_settingsArea { display: flex !important; align-items: center !important; justify-content: center !important; }",
  ].join("\n");
  document.head.appendChild(style);
})();
