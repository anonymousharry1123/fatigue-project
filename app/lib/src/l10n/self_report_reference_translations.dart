/// Personal self-report reference copy. Saved answers keep their source language.
const Map<String, Map<String, String>> selfReportReferenceTranslations = {
  'Recent personal averages': {
    'es': 'Promedios personales recientes',
    'zh-Hans': '近期个人平均值',
    'zh-Hant': '近期個人平均值',
  },
  'Your previous {period} reports': {
    'es': 'Tus registros anteriores: {period}',
    'zh-Hans': '你以往的{period}自评',
    'zh-Hant': '你以往的{period}自評',
  },
  'Each measure stays separate. Personal averages describe your reports, not a healthy or normal range.': {
    'es':
        'Cada medida se mantiene por separado. Los promedios personales describen tus registros, no un rango saludable o normal.',
    'zh-Hans': '各项分别计算。个人平均值仅反映你的自评记录，并不代表健康或正常范围。',
    'zh-Hant': '各項分別計算。個人平均值僅反映你的自評記錄，並不代表健康或正常範圍。',
  },
  'Previous {days} days · {start} to {end} · Excludes today': {
    'es': 'Últimos {days} días · Del {start} al {end} · No incluye hoy',
    'zh-Hans': '过去 {days} 天 · {start} 至 {end} · 不含今天',
    'zh-Hant': '過去 {days} 天 · {start} 至 {end} · 不含今天',
  },
  'Averages need at least {minimum} days per measure. Only matching questions and language count; the latest report per day is used. Missing answers stay missing.': {
    'es':
        'Para calcular el promedio de cada medida se necesitan al menos {minimum} días. Solo se incluyen registros con las mismas preguntas y el mismo idioma; se usa el último registro de cada día. Las respuestas que faltan se dejan sin completar.',
    'zh-Hans':
        '每项至少需要 {minimum} 天的回答才能计算平均值。仅使用问题和语言相同的记录，并采用每天的最新一份。未回答的项目保持空缺。',
    'zh-Hant':
        '每項至少需要 {minimum} 天的回答才能計算平均值。僅使用問題和語言相同的記錄，並採用每天的最新一份。未回答的項目保持空缺。',
  },
  '{measure} average: {value} / 10': {
    'es': 'Promedio de {measure}: {value} / 10',
    'zh-Hans': '{measure}平均值：{value} / 10',
    'zh-Hant': '{measure}平均值：{value} / 10',
  },
  '{count} days with an answer': {
    'es': 'Días con respuesta: {count}',
    'zh-Hans': '有回答的天数：{count}',
    'zh-Hant': '有回答的天數：{count}',
  },
  '{measure}: Not enough history': {
    'es': '{measure}: no hay suficientes registros anteriores',
    'zh-Hans': '{measure}：历史记录不足',
    'zh-Hant': '{measure}：歷史記錄不足',
  },
  '{count} of {minimum} days needed': {
    'es': '{count} de los {minimum} días necesarios',
    'zh-Hans': '已记录 {count} 天，至少需要 {minimum} 天',
    'zh-Hant': '已記錄 {count} 天，至少需要 {minimum} 天',
  },
  'Today’s answer is missing; no comparison.': {
    'es': 'Falta la respuesta de hoy; no se puede comparar.',
    'zh-Hans': '今天尚未回答，无法比较。',
    'zh-Hant': '今天尚未回答，無法比較。',
  },
  'Today: {value} / 10': {
    'es': 'Hoy: {value} / 10',
    'zh-Hans': '今天：{value} / 10',
    'zh-Hant': '今天：{value} / 10',
  },
  'Higher than your recent average': {
    'es': 'Por encima de tu promedio reciente',
    'zh-Hans': '高于你的近期平均值',
    'zh-Hant': '高於你的近期平均值',
  },
  'Lower than your recent average': {
    'es': 'Por debajo de tu promedio reciente',
    'zh-Hans': '低于你的近期平均值',
    'zh-Hant': '低於你的近期平均值',
  },
  'Matches your recent average': {
    'es': 'Coincide con tu promedio reciente',
    'zh-Hans': '与你的近期平均值相同',
    'zh-Hant': '與你的近期平均值相同',
  },
  'Comparison is unavailable for this questionnaire format.': {
    'es': 'No se puede comparar este formato de cuestionario.',
    'zh-Hans': '此问卷格式无法进行比较。',
    'zh-Hant': '此問卷格式無法進行比較。',
  },
  'Based on saved reports available now; edits can change these averages.': {
    'es':
        'Se basan en los registros guardados disponibles ahora; los cambios pueden modificar estos promedios.',
    'zh-Hans': '根据目前可用的已保存记录计算；修改记录可能会改变这些平均值。',
    'zh-Hant': '根據目前可用的已儲存記錄計算；修改記錄可能會改變這些平均值。',
  },
  'Same questionnaire language: {language}': {
    'es': 'Mismo idioma del cuestionario: {language}',
    'zh-Hans': '相同的问卷语言：{language}',
    'zh-Hant': '相同的問卷語言：{language}',
  },
};
