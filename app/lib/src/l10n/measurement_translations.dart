// Authored presentation copy for draft custom self-report measurements.
const measurementTranslations = <String, Map<String, String>>{
  "Morning Energy · Custom draft · {version} · {language}": {
    "es": "Energía matutina · Borrador personalizado · {version} · {language}",
    "zh-Hans": "早间精力 · 自定义草案 · {version} · {language}",
    "zh-Hant": "早間精力 · 自訂草案 · {version} · {language}",
  },
  "Sleep must have ended before you save it. Check the wake date and time.": {
    "es":
        "El sueño debe haber terminado antes de guardarlo. Revisa la fecha y la hora de despertar.",
    "zh-Hans": "保存时睡眠必须已经结束。请检查醒来日期和时间。",
    "zh-Hant": "儲存時睡眠必須已經結束。請檢查醒來日期和時間。",
  },
  "Morning is a quick Energy check-in. Log sleep with your Evening check-in whenever it suits you.": {
    "es":
        "Por la mañana, registra solo tu energía. Añade el sueño con tu registro de la tarde cuando te venga bien.",
    "zh-Hans": "早间只需快速记录精力。睡眠可在方便时与晚间状态一起记录。",
    "zh-Hant": "早間只需快速記錄精力。睡眠可在方便時與晚間狀態一起記錄。",
  },
  "Morning: Energy after waking, whatever the time. Evening: your daily check-in and sleep log. Choose the period yourself; both can be saved at any time.": {
    "es":
        "Mañana: tu energía al despertarte, sea la hora que sea. Tarde: tu registro diario y de sueño. Elige el período; ambos se pueden guardar a cualquier hora.",
    "zh-Hans": "早间：起床后记录精力，不限时间。晚间：记录当天状态和睡眠。自行选择时段，随时都能保存。",
    "zh-Hant": "早間：起床後記錄精力，不限時間。晚間：記錄當天狀態和睡眠。自行選擇時段，隨時都能儲存。",
  },
  "Sleep for this check-in": {
    "es": "Sueño para este registro",
    "zh-Hans": "本次状态对应的睡眠",
    "zh-Hant": "本次狀態對應的睡眠",
  },
  "Log your most recent main sleep here, even if you woke up late. There is no logging deadline. Sleep and Energy are saved separately.": {
    "es":
        "Registra aquí tu último sueño principal, aunque te hayas despertado tarde. No hay hora límite. El sueño y la energía se guardan por separado.",
    "zh-Hans": "在此记录最近一次主要睡眠，晚起也没关系。没有填写截止时间。睡眠和精力分别保存。",
    "zh-Hant": "在此記錄最近一次主要睡眠，晚起也沒關係。沒有填寫截止時間。睡眠和精力分別儲存。",
  },
  "Log or review sleep": {
    "es": "Registrar o revisar el sueño",
    "zh-Hans": "记录或查看睡眠",
    "zh-Hant": "記錄或查看睡眠",
  },
  "Wake date": {
    "es": "Fecha al despertar",
    "zh-Hans": "醒来日期",
    "zh-Hant": "醒來日期",
  },
  "Nap date": {
    "es": "Fecha de la siesta",
    "zh-Hans": "小睡日期",
    "zh-Hant": "小睡日期",
  },
  "How do you feel right now?": {
    "es": "¿Cómo te sientes ahora mismo?",
    "zh-Hans": "你现在感觉如何？",
    "zh-Hant": "你現在感覺如何？",
  },
  "Tonyo research check-in — not a clinical assessment": {
    "es": "Registro de investigación de Tonyo — no es una evaluación clínica",
    "zh-Hans": "Tonyo 研究状态记录——非临床评估",
    "zh-Hant": "Tonyo 研究狀態記錄——非臨床評估",
  },
  "These are draft custom self-report questions, not a validated questionnaire. Your answers stay separate from Tonyo’s experimental scores and are not used to train models.": {
    "es":
        "Estas preguntas personalizadas de autoinforme son un borrador, no un cuestionario validado. Tus respuestas se guardan por separado de las puntuaciones experimentales de Tonyo y no se usan para entrenar modelos.",
    "zh-Hans": "这些自定义自评问题是草案，并非经过验证的问卷。你的回答与 Tonyo 的实验性评分分开保存，不用于训练模型。",
    "zh-Hant": "這些自訂自評問題是草案，並非經過驗證的問卷。你的回答與 Tonyo 的實驗性評分分開儲存，不用於訓練模型。",
  },
  "Choose a period and answer at least one item. Other items and notes are optional; unanswered items stay missing.": {
    "es":
        "Elige un período y responde al menos a una pregunta. Las demás y las notas son opcionales; las preguntas sin responder quedan sin datos.",
    "zh-Hans": "请选择时段并至少回答一项。其他项目和备注均为可选；未回答的项目保留为空。",
    "zh-Hant": "請選擇時段並至少回答一項。其他項目和備註均為選填；未回答的項目保留為空。",
  },
  "Check-in period": {
    "es": "Período del registro",
    "zh-Hans": "记录时段",
    "zh-Hant": "記錄時段",
  },
  "Morning: after waking and beginning the day. Evening: near your usual evening time. The period you choose is kept even if you answer late.": {
    "es":
        "Mañana: después de despertarte y empezar el día. Tarde: cerca de tu hora habitual de la tarde. Se conserva el período que elijas aunque respondas más tarde.",
    "zh-Hans": "早间：醒来并开始一天之后。晚间：在平时的晚间时间附近。即使稍后才作答，也保留你选择的时段。",
    "zh-Hant": "早間：醒來並開始一天之後。晚間：在平時的晚間時間附近。即使稍後才作答，也保留你選擇的時段。",
  },
  "Choose Morning or Evening before saving.": {
    "es": "Elige Mañana o Tarde antes de guardar.",
    "zh-Hans": "保存前请选择早间或晚间。",
    "zh-Hant": "儲存前請選擇早間或晚間。",
  },
  "Select at least one rating before saving.": {
    "es": "Selecciona al menos una valoración antes de guardar.",
    "zh-Hans": "保存前请至少选择一个评分。",
    "zh-Hant": "儲存前請至少選擇一個評分。",
  },
  "Editing an earlier three-item check-in. Its original measurement version and period are preserved.": {
    "es":
        "Estás editando un registro anterior de tres preguntas. Se conservan su versión de medición y su período originales.",
    "zh-Hans": "正在编辑较早的三项状态记录。原测量版本和时段将予以保留。",
    "zh-Hant": "正在編輯較早的三項狀態記錄。原測量版本和時段將予以保留。",
  },
  "The questions below remain in their originally recorded language so this measurement is not silently changed.": {
    "es":
        "Las preguntas siguientes mantienen el idioma original del registro para evitar cambiar esta medición sin indicarlo.",
    "zh-Hans": "以下问题保留原记录语言，以免在不提示的情况下改变本次测量。",
    "zh-Hant": "以下問題保留原記錄語言，以免在不提示的情況下改變本次測量。",
  },
  "This questionnaire version cannot be edited in this app version. Its saved answers are retained.": {
    "es":
        "Esta versión del cuestionario no se puede editar en esta versión de la app. Se conservan las respuestas guardadas.",
    "zh-Hans": "此应用版本无法编辑该问卷版本。已保存的回答仍会保留。",
    "zh-Hant": "此應用程式版本無法編輯該問卷版本。已儲存的回答仍會保留。",
  },
  "right now": {"es": "ahora mismo", "zh-Hans": "此刻", "zh-Hant": "此刻"},
  "Fatigue": {"es": "Fatiga", "zh-Hans": "疲劳", "zh-Hant": "疲勞"},
  "Sleepiness": {"es": "Somnolencia", "zh-Hans": "困倦", "zh-Hant": "睏倦"},
  "Focus": {"es": "Concentración", "zh-Hans": "专注", "zh-Hant": "專注"},
  "How fatigued or drained do you feel right now?": {
    "es": "¿Cuánta fatiga o agotamiento sientes ahora mismo?",
    "zh-Hans": "你现在感觉有多疲劳或疲惫？",
    "zh-Hant": "你現在感覺有多疲勞或疲憊？",
  },
  "How sleepy do you feel right now?": {
    "es": "¿Cuánto sueño tienes ahora mismo?",
    "zh-Hans": "你现在感觉有多困？",
    "zh-Hant": "你現在感覺有多睏？",
  },
  "How easy is it for you to focus right now?": {
    "es": "¿Qué tan fácil te resulta concentrarte ahora mismo?",
    "zh-Hans": "你现在集中注意力有多容易？",
    "zh-Hant": "你現在集中注意力有多容易？",
  },
  "extremely low energy": {
    "es": "energía extremadamente baja",
    "zh-Hans": "精力极低",
    "zh-Hant": "精力極低",
  },
  "about average": {
    "es": "aproximadamente en la media",
    "zh-Hans": "大约平均水平",
    "zh-Hant": "大約平均水準",
  },
  "extremely high energy": {
    "es": "energía extremadamente alta",
    "zh-Hans": "精力极高",
    "zh-Hant": "精力極高",
  },
  "not fatigued at all": {
    "es": "sin ninguna fatiga",
    "zh-Hans": "完全不疲劳",
    "zh-Hant": "完全不疲勞",
  },
  "moderately fatigued": {
    "es": "fatiga moderada",
    "zh-Hans": "中度疲劳",
    "zh-Hant": "中度疲勞",
  },
  "extremely fatigued": {
    "es": "fatiga extrema",
    "zh-Hans": "极度疲劳",
    "zh-Hant": "極度疲勞",
  },
  "fully alert": {
    "es": "completamente alerta",
    "zh-Hans": "完全清醒",
    "zh-Hant": "完全清醒",
  },
  "moderately sleepy": {
    "es": "sueño moderado",
    "zh-Hans": "中度困倦",
    "zh-Hant": "中度睏倦",
  },
  "extremely sleepy": {
    "es": "sueño extremo",
    "zh-Hans": "极度困倦",
    "zh-Hant": "極度睏倦",
  },
  "extremely difficult to focus": {
    "es": "extremadamente difícil concentrarse",
    "zh-Hans": "极难集中注意力",
    "zh-Hant": "極難集中注意力",
  },
  "average": {"es": "en la media", "zh-Hans": "平均水平", "zh-Hant": "平均水準"},
  "extremely easy to focus": {
    "es": "extremadamente fácil concentrarse",
    "zh-Hans": "极易集中注意力",
    "zh-Hant": "極易集中注意力",
  },
  "Maxed": {"es": "Al límite", "zh-Hans": "极高", "zh-Hant": "極高"},
  "Not answered": {"es": "Sin responder", "zh-Hans": "未回答", "zh-Hant": "未回答"},
  "Skipped": {"es": "Omitido", "zh-Hans": "已跳过", "zh-Hant": "已略過"},
  "Skip this item": {
    "es": "Omitir esta pregunta",
    "zh-Hans": "跳过此项",
    "zh-Hant": "略過此項",
  },
  "Clear and skip this item": {
    "es": "Borrar y omitir esta pregunta",
    "zh-Hans": "清除并跳过此项",
    "zh-Hant": "清除並略過此項",
  },
  "Today’s self-report": {
    "es": "Autoinforme de hoy",
    "zh-Hans": "今天的自评",
    "zh-Hant": "今天的自評",
  },
  "Your reported answers, separate from experimental estimates.": {
    "es": "Tus respuestas, separadas de las estimaciones experimentales.",
    "zh-Hans": "你报告的回答，与实验性估算分开显示。",
    "zh-Hant": "你報告的回答，與實驗性估算分開顯示。",
  },
  "No self-report recorded for today.": {
    "es": "Hoy no se ha guardado ningún autoinforme.",
    "zh-Hans": "今天尚无自评记录。",
    "zh-Hant": "今天尚無自評記錄。",
  },
  "{measure}: {value}": {
    "es": "{measure}: {value}",
    "zh-Hans": "{measure}：{value}",
    "zh-Hant": "{measure}：{value}",
  },
  "{count}/6 answered · Custom draft · {version} · {language}": {
    "es":
        "{count}/6 respuestas · Borrador personalizado · {version} · {language}",
    "zh-Hans": "已回答 {count}/6 项 · 自定义草案 · {version} · {language}",
    "zh-Hant": "已回答 {count}/6 項 · 自訂草案 · {version} · {language}",
  },
  "Earlier three-item self-report; new measures were not collected.": {
    "es":
        "Autoinforme anterior de tres preguntas; no se recogieron las medidas nuevas.",
    "zh-Hans": "较早的三项自评；未收集新增测量项目。",
    "zh-Hant": "較早的三項自評；未收集新增測量項目。",
  },
  "Synthetic demo record — not a participant observation.": {
    "es":
        "Registro de demostración sintético — no es una observación de un participante.",
    "zh-Hans": "合成演示记录——并非参与者观察数据。",
    "zh-Hant": "合成示範記錄——並非參與者觀察資料。",
  },
  "Energy, fatigue, sleepiness, focus, mood, and stress · 1–10": {
    "es": "Energía, fatiga, somnolencia, concentración, ánimo y estrés · 1–10",
    "zh-Hans": "精力、疲劳、困倦、专注、心情与压力 · 1–10",
    "zh-Hant": "精力、疲勞、睏倦、專注、心情與壓力 · 1–10",
  },
  "Fatigue {value}": {
    "es": "Fatiga {value}",
    "zh-Hans": "疲劳 {value}",
    "zh-Hant": "疲勞 {value}",
  },
  "Sleepiness {value}": {
    "es": "Somnolencia {value}",
    "zh-Hans": "困倦 {value}",
    "zh-Hant": "睏倦 {value}",
  },
  "Focus {value}": {
    "es": "Concentración {value}",
    "zh-Hans": "专注 {value}",
    "zh-Hant": "專注 {value}",
  },
  "Earlier check-in (period not recorded)": {
    "es": "Registro anterior (período no registrado)",
    "zh-Hans": "较早的状态记录（未记录时段）",
    "zh-Hant": "較早的狀態記錄（未記錄時段）",
  },
  "Earlier 1–5 self-report · Original answers": {
    "es": "Autoinforme anterior de 1–5 · Respuestas originales",
    "zh-Hans": "较早的 1–5 自评 · 原始回答",
    "zh-Hant": "較早的 1–5 自評 · 原始回答",
  },
  "This earlier record cannot be edited with the current scales. Its original answers are retained.": {
    "es":
        "Este registro anterior no se puede editar con las escalas actuales. Se conservan sus respuestas originales.",
    "zh-Hans": "无法使用当前量表编辑此较早的记录。原始回答仍予以保留。",
    "zh-Hant": "無法使用目前量表編輯此較早的記錄。原始回答仍予以保留。",
  },
};
