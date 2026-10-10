/// Authored labels for descriptive raw self-report and sleep views.
const Map<String, Map<String, String>> selfReportTrendsTranslations = {
  'Self-report trends': {
    'es': 'Tendencias de tus respuestas',
    'zh-Hans': '自评趋势',
    'zh-Hant': '自評趨勢',
  },
  'Your raw reports and preceding main sleep': {
    'es': 'Tus respuestas originales y el sueño principal anterior',
    'zh-Hans': '原始自评与此前的主要睡眠',
    'zh-Hant': '原始自評與此前的主要睡眠',
  },
  'Measure': {'es': 'Medida', 'zh-Hans': '测量项目', 'zh-Hant': '測量項目'},
  'Reported period': {
    'es': 'Período indicado',
    'zh-Hans': '所选自评时段',
    'zh-Hant': '所選自評時段',
  },
  'Questionnaire language': {
    'es': 'Idioma del cuestionario',
    'zh-Hans': '问卷语言',
    'zh-Hant': '問卷語言',
  },
  '{start} to {end} · {days} captured dates': {
    'es': 'Del {start} al {end} · {days} fechas locales de registro',
    'zh-Hans': '{start} 至 {end} · 按记录时的当地日期，共 {days} 天',
    'zh-Hant': '{start} 至 {end} · 按記錄時的當地日期，共 {days} 天',
  },
  'Source: reports and sleep records saved on this device.': {
    'es':
        'Fuente: respuestas y registros de sueño guardados en este dispositivo.',
    'zh-Hans': '来源：此设备上保存的自评和睡眠记录。',
    'zh-Hant': '來源：此裝置上儲存的自評和睡眠紀錄。',
  },
  'Latest compatible report per date and period. Only the current draft version with matching questions and language is included. Demo records are excluded.': {
    'es':
        'Se usa la última respuesta compatible de cada fecha y período. Solo se incluye la versión actual del borrador, con las mismas preguntas e idioma. Se excluyen los registros de demostración.',
    'zh-Hans': '每个日期和时段采用最新的兼容自评。仅纳入当前草案版本中问题和语言一致的记录；演示记录不计入。',
    'zh-Hant': '每個日期和時段採用最新的相容自評。僅納入目前草案版本中問題和語言一致的紀錄；示範紀錄不計入。',
  },
  '{reports} of {days} dates have a report · {answered} answers · {missing} missing': {
    'es':
        'Fechas con registro: {reports} de {days} · Respuestas: {answered} · Sin respuesta: {missing}',
    'zh-Hans': '{days} 天中有 {reports} 天有自评 · 已回答 {answered} 天 · 缺失 {missing} 天',
    'zh-Hant': '{days} 天中有 {reports} 天有自評 · 已回答 {answered} 天 · 缺失 {missing} 天',
  },
  'Ratings over time': {
    'es': 'Valoraciones a lo largo del tiempo',
    'zh-Hans': '自评分值随时间的变化',
    'zh-Hant': '自評分值隨時間的變化',
  },
  'Raw {measure} ratings, 1–10. {count} answered dates. Gaps are missing answers. Exact values are in the per-date records.': {
    'es':
        'Valoraciones originales de {measure}, del 1 al 10. Hay respuestas en {count} fechas. Los espacios indican respuestas ausentes. Los valores exactos están en los registros por fecha.',
    'zh-Hans': '{measure}原始评分，范围为 1–10。有 {count} 天的回答。空缺表示未回答。精确数值见按日期列出的记录。',
    'zh-Hant': '{measure}原始評分，範圍為 1–10。有 {count} 天的回答。空缺表示未回答。精確數值見按日期列出的紀錄。',
  },
  'Captured date': {
    'es': 'Fecha local del registro',
    'zh-Hans': '记录时的当地日期',
    'zh-Hant': '記錄時的當地日期',
  },
  'No matching self-reports in this window.': {
    'es': 'No hay respuestas compatibles en este intervalo.',
    'zh-Hans': '此时间范围内没有匹配的自评。',
    'zh-Hant': '此時間範圍內沒有符合條件的自評。',
  },
  'No answers for this measure in this window.': {
    'es': 'No hay respuestas para esta medida en este intervalo.',
    'zh-Hans': '此时间范围内没有该项目的回答。',
    'zh-Hant': '此時間範圍內沒有該項目的回答。',
  },
  'Charts appear after 8 answered dates. Available answers are shown below.': {
    'es':
        'El gráfico aparece cuando hay respuestas en 8 fechas. Las respuestas disponibles se muestran a continuación.',
    'zh-Hans': '有 8 天的回答后显示图表。现有回答列在下方。',
    'zh-Hant': '有 8 天的回答後顯示圖表。現有回答列在下方。',
  },
  '{date}: {value} / 10': {
    'es': '{date}: {value} / 10',
    'zh-Hans': '{date}：{value} / 10',
    'zh-Hant': '{date}：{value} / 10',
  },
  'Ratings and preceding main sleep': {
    'es': 'Valoraciones y sueño principal anterior',
    'zh-Hans': '自评分值与此前的主要睡眠',
    'zh-Hant': '自評分值與此前的主要睡眠',
  },
  '{pairs} paired answers · {unpaired} answers without a sleep match': {
    'es':
        'Respuestas con sueño emparejado: {pairs} · Sin sueño emparejado: {unpaired}',
    'zh-Hans': '{pairs} 份回答已匹配睡眠 · {unpaired} 份回答未匹配到睡眠',
    'zh-Hant': '{pairs} 份回答已配對睡眠 · {unpaired} 份回答未配對到睡眠',
  },
  'Sleep ends before the report within 24 hours. Only one eligible main sleep is paired; naps and ambiguous matches are excluded. These paired records do not show cause or medical significance.': {
    'es':
        'El sueño termina en las 24 horas previas a la respuesta. Se empareja un único sueño principal compatible; se excluyen las siestas y las coincidencias ambiguas. Estos pares no demuestran causas ni relevancia médica.',
    'zh-Hans':
        '睡眠须在自评前 24 小时内结束。仅匹配一段符合条件的主要睡眠；不纳入小睡或无法明确匹配的记录。这些配对记录不能说明因果关系或医学意义。',
    'zh-Hant':
        '睡眠須在自評前 24 小時內結束。僅配對一段符合條件的主要睡眠；不納入小睡或無法明確配對的紀錄。這些配對紀錄不能說明因果關係或醫學意義。',
  },
  'Pairs use records available now; later edits can change them.': {
    'es':
        'Los pares usan los registros disponibles ahora; las ediciones posteriores pueden cambiarlos.',
    'zh-Hans': '配对使用目前可用的记录；后续修改可能改变配对结果。',
    'zh-Hant': '配對使用目前可用的紀錄；後續修改可能改變配對結果。',
  },
  '{count} paired records. Horizontal axis: preceding main sleep in hours. Vertical axis: raw {measure} rating, 1–10. Exact pairs and sources are in the per-date records.': {
    'es':
        '{count} registros emparejados. Eje horizontal: sueño principal anterior en horas. Eje vertical: valoración original de {measure}, del 1 al 10. Los pares exactos y sus fuentes están en los registros por fecha.',
    'zh-Hans':
        '{count} 对记录。横轴：此前主要睡眠的小时数。纵轴：{measure}原始评分，范围为 1–10。精确配对值及来源见按日期列出的记录。',
    'zh-Hant':
        '{count} 對紀錄。橫軸：此前主要睡眠的小時數。縱軸：{measure}原始評分，範圍為 1–10。精確配對值及來源見按日期列出的紀錄。',
  },
  'Preceding main sleep (hours)': {
    'es': 'Sueño principal anterior (horas)',
    'zh-Hans': '此前主要睡眠（小时）',
    'zh-Hant': '此前主要睡眠（小時）',
  },
  'No paired answers in this window.': {
    'es': 'No hay respuestas con sueño emparejado en este intervalo.',
    'zh-Hans': '此时间范围内没有匹配到睡眠的回答。',
    'zh-Hant': '此時間範圍內沒有配對到睡眠的回答。',
  },
  'These paired records have no variation to compare.': {
    'es':
        'Estos pares tienen los mismos valores; no hay variaciones que comparar.',
    'zh-Hans': '这些配对记录的数值均相同，没有可比较的变化。',
    'zh-Hant': '這些配對紀錄的數值均相同，沒有可比較的變化。',
  },
  'A sleep chart appears after 8 paired answers. Available pairs are shown below.': {
    'es':
        'El gráfico de sueño aparece cuando hay 8 respuestas emparejadas. Los pares disponibles se muestran a continuación.',
    'zh-Hans': '有 8 份回答匹配到睡眠后显示图表。现有配对列在下方。',
    'zh-Hant': '有 8 份回答配對到睡眠後顯示圖表。現有配對列在下方。',
  },
  '{date}: {value} / 10 · {hours} hours of sleep': {
    'es': '{date}: {value} / 10 · {hours} horas de sueño',
    'zh-Hans': '{date}：{value} / 10 · 睡眠 {hours} 小时',
    'zh-Hant': '{date}：{value} / 10 · 睡眠 {hours} 小時',
  },
  'Per-date records and missing answers': {
    'es': 'Registros por fecha y respuestas ausentes',
    'zh-Hans': '每日记录与缺失回答',
    'zh-Hant': '每日紀錄與缺失回答',
  },
  'Exact values, sleep sources and unmatched reasons': {
    'es': 'Valores exactos, fuentes del sueño y motivos sin emparejamiento',
    'zh-Hans': '精确数值、睡眠来源和未匹配原因',
    'zh-Hant': '精確數值、睡眠來源和未配對原因',
  },
  'No matching self-report on this date.': {
    'es': 'No hay una respuesta compatible en esta fecha.',
    'zh-Hans': '此日期没有匹配的自评。',
    'zh-Hant': '此日期沒有符合條件的自評。',
  },
  'Preceding main sleep: {hours} hours': {
    'es': 'Sueño principal anterior: {hours} horas',
    'zh-Hans': '此前主要睡眠：{hours} 小时',
    'zh-Hant': '此前主要睡眠：{hours} 小時',
  },
  '{source} · {availability}': {
    'es': '{source} · {availability}',
    'zh-Hans': '{source} · {availability}',
    'zh-Hant': '{source} · {availability}',
  },
  'Apple Health': {
    'es': 'Apple Health',
    'zh-Hans': 'Apple 健康',
    'zh-Hant': 'Apple 健康',
  },
  'Recording time available': {
    'es': 'Hora de registro conocida',
    'zh-Hans': '记录保存时间已知',
    'zh-Hant': '紀錄儲存時間已知',
  },
  'Availability time unknown': {
    'es': 'Se desconoce cuándo estuvo disponible',
    'zh-Hans': '记录何时可用尚不明确',
    'zh-Hant': '紀錄何時可用尚不明確',
  },
  'Raw rating (1–10)': {
    'es': 'Valoración original (1–10)',
    'zh-Hans': '原始评分（1–10）',
    'zh-Hant': '原始評分（1–10）',
  },
  'Check-in is not eligible for sleep pairing.': {
    'es': 'Esta respuesta no cumple los requisitos para emparejarla con sueño.',
    'zh-Hans': '此自评不符合睡眠匹配条件。',
    'zh-Hant': '此自評不符合睡眠配對條件。',
  },
  'No eligible main sleep in the preceding 24 hours.': {
    'es': 'No hay sueño principal compatible en las 24 horas previas.',
    'zh-Hans': '此前 24 小时内没有符合条件的主要睡眠。',
    'zh-Hant': '此前 24 小時內沒有符合條件的主要睡眠。',
  },
  'Multiple sleep summaries could match this check-in.': {
    'es': 'Varios resúmenes de sueño podrían corresponder a esta respuesta.',
    'zh-Hans': '多份睡眠汇总都可能与此自评匹配。',
    'zh-Hant': '多份睡眠摘要都可能與此自評配對。',
  },
};
