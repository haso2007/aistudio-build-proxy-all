import time
import os
import re
from playwright.sync_api import Page, expect

def handle_untrusted_dialog(page: Page, logger=None):
    """
    检查并处理 "Last modified by..." 的弹窗。
    如果弹窗出现，则点击 "OK" 按钮。
    """
    ok_button_locator = page.get_by_role("button", name="OK")

    try:
        if ok_button_locator.is_visible(timeout=10000): # 等待最多10秒
            logger.info(f"检测到弹窗，正在点击 'OK' 按钮...")
            
            ok_button_locator.click(force=True)
            logger.info(f"'OK' 按钮已点击。")
            expect(ok_button_locator).to_be_hidden(timeout=1000)
            logger.info(f"弹窗已确认关闭。")
        else:
            logger.info(f"在10秒内未检测到弹窗，继续执行...")
    except Exception as e:
        logger.info(f"检查弹窗时发生意外：{e}，将继续执行...")

def handle_successful_navigation(page: Page, logger, cookie_file_config, force_enable_search: bool = True):
    """
    在成功导航到目标页面后，执行后续操作（处理弹窗、截图、保持运行）。
    """
    logger.info("已成功到达目标页面。")
    page.click('body') # 给予页面焦点

    # 检查并处理 "Last modified by..." 的弹窗
    handle_untrusted_dialog(page, logger=logger)

    # 处理首次进入时的引导弹窗（例如 "It's time to build"）
    try:
        dismissed = dismiss_onboarding_modal(page, logger=logger)
        if dismissed:
            logger.info("已关闭首屏引导弹窗（It's time to build 等）。")
    except Exception as e:
        logger.info(f"处理首屏引导弹窗时出现异常：{e}")

    # 尝试开启 Grounding with Google Search（按配置开关）
    if force_enable_search:
        try:
            # 先尝试打开设置面板
            open_settings_panel(page, logger=logger)
            enabled = enable_grounding_with_google_search(page, logger=logger)
            if enabled:
                logger.info("已确保开启 Grounding with Google Search。")
            else:
                logger.warning("未能确认开启 Grounding with Google Search（可能UI结构不同或权限受限）。")
                # 失败时留证据
                try:
                    page.screenshot(path=os.path.join('logs', f"WARN_search_toggle_not_confirmed_{cookie_file_config}.png"), full_page=True)
                except Exception:
                    pass
        except Exception as e:
            logger.warning(f"尝试开启 Grounding with Google Search 时发生异常: {e}")

    # 等待页面加载和渲染后截图
    logger.info("等待15秒以便页面完全渲染...")
    time.sleep(15)
    
    screenshot_dir = 'logs'
    screenshot_filename = os.path.join(screenshot_dir, f"screenshot_{cookie_file_config}_{int(time.time())}.png")
    try:
        page.screenshot(path=screenshot_filename, full_page=True)
        logger.info(f"已截屏到: {screenshot_filename}")
    except Exception as e:
        logger.error(f"截屏时出错: {e}")
        
    logger.info("实例将保持运行状态。每10秒点击一次页面以保持活动。")
    while True:
        try:
            page.click('body', force=True) 
            time.sleep(10)
        except Exception as e:
            logger.error(f"在保持活动循环中出错: {e}")
            break # 如果页面关闭或出错，则退出循环


def enable_grounding_with_google_search(page: Page, logger=None) -> bool:
    """
    尝试在 AI Studio 的设置/工具面板中开启 "Grounding with Google Search"。
    - 优先通过可访问性 role=switch + 名称匹配开启。
    - 回退策略：根据文本定位邻近的 switch 或 mat-slide-toggle。
    返回是否确认开启成功。
    """
    def _log(msg: str):
        if logger:
            logger.info(msg)

    # 1) 展开 "Tools/工具" 折叠面板（如果存在）
    try:
        for label in [re.compile(r"^Tools$", re.I), re.compile(r"^工具$", re.I)]:
            btn = page.get_by_role("button", name=label)
            if btn.count() > 0:
                try:
                    aria_expanded = btn.first.get_attribute("aria-expanded")
                    if aria_expanded == "false":
                        _log("检测到 Tools 折叠面板处于收起状态，尝试展开……")
                        btn.first.click()
                        page.wait_for_timeout(300)
                except Exception:
                    # 某些结构不是按钮式折叠，忽略错误
                    pass
    except Exception:
        pass

    # 2) 优先直接用 role=switch 名称定位
    name_patterns = [
        re.compile(r"Grounding with Google Search", re.I),
        re.compile(r"Google\s*Search", re.I),
        re.compile(r"Google\s*搜索", re.I),
        re.compile(r"谷歌\s*搜索", re.I),
        re.compile(r"联网\s*搜索", re.I),
        re.compile(r"检索", re.I),
        re.compile(r"Grounding", re.I),
    ]

    for pat in name_patterns:
        switch = page.get_by_role("switch", name=pat)
        if switch.count() > 0:
            state = (switch.first.get_attribute("aria-checked") or "").lower()
            if state != "true":
                _log("找到 Grounding with Google Search 开关，当前为关闭，尝试打开……")
                switch.first.click()
                page.wait_for_timeout(300)
            # 再次确认
            state2 = (switch.first.get_attribute("aria-checked") or "").lower()
            return state2 == "true"

    # 3) 回退：根据文本定位附近的 switch/mat-slide-toggle
    text_anchor = None
    for pat in [
        re.compile(r"Grounding with Google Search", re.I),
        re.compile(r"Google\s*Search", re.I),
        re.compile(r"Google\s*搜索", re.I),
        re.compile(r"谷歌\s*搜索", re.I),
        re.compile(r"联网\s*搜索", re.I),
        re.compile(r"检索", re.I),
        re.compile(r"Grounding", re.I),
    ]:
        loc = page.get_by_text(pat, exact=False)
        if loc.count() > 0:
            text_anchor = loc.first
            break

    if text_anchor is not None:
        try:
            text_anchor.scroll_into_view_if_needed()
        except Exception:
            pass
        # 尝试多个候选：switch按钮、复选框、mat-slide-toggle容器或其label
        candidates = [
            text_anchor.locator("xpath=ancestor::*[self::mat-slide-toggle or @role='group' or @role='region'][1]//button[@role='switch']"),
            text_anchor.locator("xpath=ancestor::*[self::mat-slide-toggle or @role='group' or @role='region'][1]//input[@type='checkbox']"),
            text_anchor.locator("xpath=ancestor::mat-slide-toggle[1]")
        ]
        for cand in candidates:
            if cand.count() > 0:
                try:
                    state = (cand.first.get_attribute("aria-checked") or "").lower()
                except Exception:
                    state = ""
                _log("通过文本定位到候选开关，尝试打开……")
                try:
                    cand.first.click()
                except Exception:
                    try:
                        cand.first.locator("label").first.click()
                    except Exception:
                        pass
                page.wait_for_timeout(300)
                # 再确认一次
                try:
                    state2 = (cand.first.get_attribute("aria-checked") or "").lower()
                    if state2 == "true":
                        return True
                except Exception:
                    # 某些实现没有 aria-checked，可通过再次查找 role=switch 校验
                    sw = page.get_by_role("switch", name=re.compile(r"Google|搜索|Grounding", re.I))
                    if sw.count() > 0 and (sw.first.get_attribute("aria-checked") or "").lower() == "true":
                        return True

    return False


def open_settings_panel(page: Page, logger=None) -> bool:
    """尝试打开设置面板（齿轮按钮或名为 Settings/设置 的按钮）。"""
    def _log(msg: str):
        if logger:
            logger.info(msg)

    # 1) aria-label 方式
    for sel in [
        "button[aria-label='Settings']",
        "button[aria-label*='Settings' i]",
        "button[aria-label='设置']",
        "button[aria-label*='设置']",
    ]:
        btn = page.locator(sel)
        if btn.count() > 0:
            try:
                _log(f"尝试点击设置按钮: {sel}")
                btn.first.click()
                page.wait_for_timeout(300)
                return True
            except Exception:
                pass

    # 2) role 名称方式
    for pat in [re.compile(r"^Settings$", re.I), re.compile(r"^设置$", re.I)]:
        btn = page.get_by_role("button", name=pat)
        if btn.count() > 0:
            try:
                _log("尝试点击设置按钮（role=button）")
                btn.first.click()
                page.wait_for_timeout(300)
                return True
            except Exception:
                pass

    return False


def dismiss_onboarding_modal(page: Page, logger=None) -> bool:
    """关闭 AI Studio 首屏引导弹窗（如 "It's time to build"）。"""
    def _log(msg: str):
        if logger:
            logger.info(msg)

    # 1) 直接寻找包含特征文案的对话框
    try:
        modal_texts = [
            re.compile(r"It's time to build", re.I),
            re.compile(r"Use Google AI Studio", re.I),
            re.compile(r"Try Gemini", re.I),
            re.compile(r"Get API key", re.I),
        ]
        for pat in modal_texts:
            box = page.get_by_text(pat, exact=False)
            if box.count() > 0 and box.first.is_visible():
                _log("检测到首屏引导弹窗内容，尝试关闭……")
                # 优先点击关闭按钮
                for sel in [
                    "button[aria-label='Close']",
                    "button[aria-label*='Close' i]",
                    "button[aria-label='关闭']",
                ]:
                    btn = page.locator(sel)
                    if btn.count() > 0 and btn.first.is_visible():
                        try:
                            btn.first.click()
                            page.wait_for_timeout(300)
                            return True
                        except Exception:
                            pass

                # 回退：role 名称方式
                for patBtn in [re.compile(r"^Close$", re.I), re.compile(r"^关闭$", re.I), re.compile(r"^Dismiss$", re.I), re.compile(r"^×$")]:
                    btn = page.get_by_role("button", name=patBtn)
                    if btn.count() > 0 and btn.first.is_visible():
                        try:
                            btn.first.click()
                            page.wait_for_timeout(300)
                            return True
                        except Exception:
                            pass

                # 再退：按 ESC
                try:
                    page.keyboard.press('Escape')
                    page.wait_for_timeout(200)
                except Exception:
                    pass

                # 再检查是否仍存在
                if box.count() == 0 or not box.first.is_visible():
                    return True
    except Exception:
        pass

    return False
