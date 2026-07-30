import re
from dataclasses import dataclass


ADULT_HELP_RESPONSE = "这件事很重要，请马上告诉身边你信任的大人，让他来帮助你。"
SAFE_FALLBACK_RESPONSE = "这个话题我不太适合回答，我们换一个轻松的话题吧。"
PRIVACY_RESPONSE = "不用告诉我这些私人信息，我们聊聊你喜欢的故事或游戏吧。"


@dataclass(frozen=True, slots=True)
class SafetyDecision:
    allowed: bool
    category: str = "allowed"
    safe_response: str = ""


class SafetyGuard:
    _prompt_injection = re.compile(
        r"(忽略|无视|绕过).{0,8}(规则|提示词|指令)|系统提示词|developer message",
        re.IGNORECASE,
    )
    _high_risk = re.compile(
        r"自杀|自残|不想活|有人打我|虐待|性侵|猥亵|不要告诉.{0,6}(爸爸|妈妈|家长|老师)",
        re.IGNORECASE,
    )
    _adult = re.compile(r"色情|做爱|裸照|成人视频", re.IGNORECASE)
    _private_input = re.compile(
        r"(?:1[3-9]\d{9})|(?:我(?:家|住)在.{1,30}(?:路|街|小区))|(?:我的学校是)",
        re.IGNORECASE,
    )
    _private_request = re.compile(
        r"(?:告诉|发给|给我).{0,12}(?:姓名|学校|住址|地址|手机号|电话号码|照片|账号)"
        r"|(?:你|你的).{0,5}(?:学校|住址|地址|手机号|电话号码|照片|账号).{0,6}(?:什么|多少|发来|告诉)",
        re.IGNORECASE,
    )
    _dangerous_output = re.compile(
        r"不要告诉.{0,8}(爸爸|妈妈|家长|老师)|只有我理解你|不要离开我|买下来|偷偷付款",
        re.IGNORECASE,
    )
    _url = re.compile(r"https?://\S+|www\.\S+", re.IGNORECASE)
    _markdown = re.compile(r"[*_#`>|~]+")

    def check_input(self, text: str) -> SafetyDecision:
        normalized = text.strip()
        if self._prompt_injection.search(normalized):
            return SafetyDecision(False, "prompt_injection", SAFE_FALLBACK_RESPONSE)
        if self._high_risk.search(normalized):
            return SafetyDecision(False, "high_risk", ADULT_HELP_RESPONSE)
        if self._adult.search(normalized):
            return SafetyDecision(False, "adult_content", SAFE_FALLBACK_RESPONSE)
        if self._private_input.search(normalized):
            return SafetyDecision(False, "private_information", PRIVACY_RESPONSE)
        return SafetyDecision(True)

    def sanitize_output(self, text: str, max_characters: int) -> str:
        normalized = text.strip()
        if self._private_request.search(normalized) or self._dangerous_output.search(normalized):
            return SAFE_FALLBACK_RESPONSE
        normalized = self._url.sub("", normalized)
        normalized = self._markdown.sub("", normalized)
        normalized = re.sub(r"\s+", " ", normalized).strip()
        if not normalized:
            return SAFE_FALLBACK_RESPONSE
        if len(normalized) > max_characters:
            normalized = normalized[:max_characters].rstrip("，、；： ")
            if len(normalized) < max_characters and normalized[-1:] not in "。！？":
                normalized += "。"
        return normalized
