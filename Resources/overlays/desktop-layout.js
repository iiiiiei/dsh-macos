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
 *  - 折叠态侧栏宽度 = 红灯左距×2 + 红绿灯组宽 = 7×2+54 = 68（含右边框的视觉总宽）
 *  - 折叠态官方 56px 轨保持原生内边距（图标原生 x 不动），整体在侧栏内居中
 *    → 图标中心 = 侧栏中心 = 黄灯中心 x=34
 */
(function () {
  if (document.getElementById("dsh-desktop-layout")) return;
  var style = document.createElement("style");
  style.id = "dsh-desktop-layout";
  style.textContent = [
    // 展开态：logo 行从红绿灯行下方开始（原生注入红绿灯行高）
    ".hHd-Xa_logoRow { margin-top: var(--dsh-traffic-inset, 28px) !important; }",
    // 折叠态：侧栏宽度以红绿灯系统默认绝对位置为锚（左缘 7 / 右缘 61 / 组宽 54）。
    // 宽 = 红灯左距×2 + 组宽 = 68；box-sizing: border-box 使视觉总宽（含 1px 右边框）
    // 精确等于 68 —— 绿灯距右侧边框竖直边界 = 红灯距左视窗框 = 7（目标公式严格成立）
    ".pI_x6G_sidebarCol:has(.hHd-Xa_collapsed) { box-sizing: border-box !important; width: calc(var(--dsh-traffic-left) * 2 + var(--dsh-traffic-width) - 8px) !important; }",
    // 折叠态：官方 56px 轨保持原生内边距（图标原生 x 数值不动），
    // 整体在 68px 侧栏内水平居中 → 轨中心 = 侧栏中心 = 黄灯中心 x=34
    ".pI_x6G_sidebarCol:has(.hHd-Xa_collapsed) .hHd-Xa_root { width: 56px !important; margin-left: auto !important; margin-right: auto !important; }",
    // 折叠态：会话图标列内部统一按中心对齐（原生 sectionHeader/行图标靠左，
    // 由容器 align-items: center 在 56px 轨内容区内居中，不改各图标原生 x）
    ".pI_x6G_sidebarCol:has(.hHd-Xa_collapsed) .qDHVXG_root { align-items: center !important; }",
    // 主内容区让出透明标题栏行：padding = 拖拽带行高 - 顶栏固有间距 12px，
    // 使顶栏最高元素（session log 按钮）上边框贴紧拖拽带下限
    ".pI_x6P_centerCol, .pI_x6G_centerCol { padding-top: calc(var(--dsh-traffic-inset, 28px) - 12px) !important; }",
    // 详情列同样让出拖拽带（原生关闭按钮 t=14 位于拖拽带内，会被拖拽带挡住）
    ".pI_x6G_detailsCol { padding-top: calc(var(--dsh-traffic-inset, 28px) - 12px) !important; }",
    // 会话选中框/悬停框：与新会话按钮（hHd-Xa_brand）同宽同缘——
    // 实测按钮矩形 216/16/232（距侧栏左缘 16、右缘 48），行容器（HoverCard
    // 包裹层 _root_1b2ny_3）为 12..276，故 ml=4、mr=44 使选中框恰好
    // 16..232 与按钮完全重合；宽度仍随侧栏弹性变化（原生动态特性不动）
    ".YDXeBa_sessionRow { box-sizing: border-box !important; width: calc(100% - 48px) !important; margin-left: 4px !important; margin-right: 44px !important; }",
    // 折叠态设置图标在底部区域内垂直居中
    ".hHd-Xa_settingsArea { display: flex !important; align-items: center !important; justify-content: center !important; }",
  ].join("\n");
  document.head.appendChild(style);
})();
