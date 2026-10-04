// Main navigation, observation, Coach, and Insights copy. Stored identifiers remain English.
const coreTranslations = <String, Map<String, String>>{
  "Language": {"es": "Idioma", "zh-Hans": "语言", "zh-Hant": "語言"},
  "Close": {"es": "Cerrar", "zh-Hans": "关闭", "zh-Hant": "關閉"},
  "Could not save your language. Please try again.": {
    "es": "No se pudo guardar el idioma. Inténtalo de nuevo.",
    "zh-Hans": "无法保存语言，请重试。",
    "zh-Hant": "無法保存語言，請重試。",
  },
  "Some technical details and notifications are still in English.": {
    "es": "Algunos detalles técnicos y notificaciones siguen en inglés.",
    "zh-Hans": "部分技术详情和通知仍以英语显示。",
    "zh-Hant": "部分技術詳情和通知仍以英語顯示。",
  },
  "Today": {"es": "Hoy", "zh-Hans": "今天", "zh-Hant": "今天"},
  "Forecast": {"es": "Pronóstico", "zh-Hans": "预测", "zh-Hant": "預測"},
  "Add": {"es": "Añadir", "zh-Hans": "添加", "zh-Hant": "添加"},
  "Coach": {"es": "Asistente", "zh-Hans": "指导", "zh-Hant": "指導"},
  "Profile": {"es": "Perfil", "zh-Hans": "个人资料", "zh-Hant": "個人資料"},
  "Insights": {"es": "Tendencias", "zh-Hans": "数据洞察", "zh-Hant": "數據洞察"},
  "Energy": {"es": "Energía", "zh-Hans": "精力", "zh-Hant": "精力"},
  "Cognitive": {"es": "Cognitivo", "zh-Hans": "认知", "zh-Hant": "認知"},
  "EXPERIMENTAL ESTIMATES": {
    "es": "ESTIMACIONES EXPERIMENTALES",
    "zh-Hans": "实验性估算",
    "zh-Hant": "實驗性估算",
  },
  "Experimental estimates": {
    "es": "Estimaciones experimentales",
    "zh-Hans": "实验性估算",
    "zh-Hant": "實驗性估算",
  },
  "Saved snapshot": {
    "es": "Resumen guardado",
    "zh-Hans": "已保存的快照",
    "zh-Hant": "已保存的快照",
  },
  "Live estimate": {
    "es": "Estimación actual",
    "zh-Hans": "当前估算",
    "zh-Hant": "當前估算",
  },
  "Not enough information to estimate": {
    "es": "No hay información suficiente para estimar",
    "zh-Hans": "信息不足，无法估算",
    "zh-Hant": "信息不足，無法估算",
  },
  "These heuristic scores are not recovery or exercise clearance.": {
    "es":
        "Estas puntuaciones heurísticas no confirman la recuperación ni autorizan hacer ejercicio.",
    "zh-Hans": "这些启发式评分不能证明已恢复，也不能作为运动许可。",
    "zh-Hant": "這些啓發式評分不能證明已恢復，也不能作為運動許可。",
  },
  "ESTIMATED ENERGY SCORE": {
    "es": "PUNTUACIÓN ESTIMADA DE ENERGÍA",
    "zh-Hans": "估算精力评分",
    "zh-Hant": "估算精力評分",
  },
  "ESTIMATED COGNITIVE SCORE": {
    "es": "PUNTUACIÓN COGNITIVA ESTIMADA",
    "zh-Hans": "估算认知评分",
    "zh-Hant": "估算認知評分",
  },
  "Why these scores?": {
    "es": "¿Por qué estas puntuaciones?",
    "zh-Hans": "为什么是这些评分？",
    "zh-Hant": "為什麼是這些評分？",
  },
  "Today’s signals": {
    "es": "Señales de hoy",
    "zh-Hans": "今日信号",
    "zh-Hant": "今日信號",
  },
  "Personal context": {
    "es": "Contexto personal",
    "zh-Hans": "个人背景",
    "zh-Hant": "個人背景",
  },
  "What shaped today": {
    "es": "Factores de hoy",
    "zh-Hans": "今日影响因素",
    "zh-Hant": "今日影響因素",
  },
  "Updating…": {"es": "Actualizando…", "zh-Hans": "正在更新…", "zh-Hant": "正在更新…"},
  "Refresh": {"es": "Actualizar", "zh-Hans": "刷新", "zh-Hant": "刷新"},
  "Energy factors": {
    "es": "Factores de energía",
    "zh-Hans": "精力因素",
    "zh-Hant": "精力因素",
  },
  "Today’s score factors": {
    "es": "Factores de la puntuación de hoy",
    "zh-Hans": "今日评分因素",
    "zh-Hant": "今日評分因素",
  },
  "Cognitive factors": {
    "es": "Factores cognitivos",
    "zh-Hans": "认知因素",
    "zh-Hant": "認知因素",
  },
  "WHAT SHAPED THIS ESTIMATE": {
    "es": "FACTORES DE ESTA ESTIMACIÓN",
    "zh-Hans": "影响本次估算的因素",
    "zh-Hant": "影響本次估算的因素",
  },
  "These experimental estimates use available workload, check-in, reaction, and heart observations. Sleep, caffeine, fluid volume, and exercise duration do not earn score points. This is not a medical assessment.": {
    "es":
        "Estas estimaciones experimentales usan los registros disponibles de carga de trabajo, autoevaluación, reacción y corazón. El sueño, la cafeína, el volumen de líquidos y la duración del ejercicio no suman puntos. No es una evaluación médica.",
    "zh-Hans": "这些实验性估算使用现有的工作负荷、自评、反应和心脏观测记录。睡眠、咖啡因、饮水量和运动时长不会获得加分。这不是医学评估。",
    "zh-Hant": "這些實驗性估算使用現有的工作負荷、自評、反應和心臟觀測記錄。睡眠、咖啡因、飲水量和運動時長不會獲得加分。這不是醫學評估。",
  },
  "No current estimate": {
    "es": "Sin estimación actual",
    "zh-Hans": "暂无当前估算",
    "zh-Hant": "暫無當前估算",
  },
  "First Cognitive Score · comparison starts tomorrow": {
    "es": "Primera puntuación cognitiva · la comparación empieza mañana",
    "zh-Hans": "首次认知评分 · 明天开始比较",
    "zh-Hant": "首次認知評分 · 明天開始比較",
  },
  "No change from yesterday": {
    "es": "Sin cambios respecto a ayer",
    "zh-Hans": "与昨天相比无变化",
    "zh-Hant": "與昨天相比無變化",
  },
  "{change} points from yesterday": {
    "es": "{change} puntos respecto a ayer",
    "zh-Hans": "较昨天变化 {change} 分",
    "zh-Hant": "較昨天變化 {change} 分",
  },
  "Latest retained observation: {date} · {age} ago. This is not a current measurement.": {
    "es":
        "Último registro conservado: {date} · hace {age}. No es una medición actual.",
    "zh-Hans": "最近保留的观测：{date} · {age}前。这不是当前测量。",
    "zh-Hant": "最近保留的觀測：{date} · {age}前。這不是當前測量。",
  },
  "{count} days": {
    "es": "{count} días",
    "zh-Hans": "{count} 天",
    "zh-Hant": "{count} 天",
  },
  "{count} day": {
    "es": "{count} día",
    "zh-Hans": "{count} 天",
    "zh-Hant": "{count} 天",
  },
  "{count} hours": {
    "es": "{count} horas",
    "zh-Hans": "{count} 小时",
    "zh-Hant": "{count} 小時",
  },
  "{count} hour": {
    "es": "{count} hora",
    "zh-Hans": "{count} 小时",
    "zh-Hant": "{count} 小時",
  },
  "{count} minutes": {
    "es": "{count} minutos",
    "zh-Hans": "{count} 分钟",
    "zh-Hant": "{count} 分鐘",
  },
  "{count} minute": {
    "es": "{count} minuto",
    "zh-Hans": "{count} 分钟",
    "zh-Hant": "{count} 分鐘",
  },
  "{coverage} scored inputs · {quality}% data quality · {freshness}% fresh": {
    "es":
        "{coverage} entradas puntuadas · {quality}% de calidad de datos · {freshness}% de actualidad",
    "zh-Hans": "{coverage} 项评分输入 · 数据质量 {quality}% · 新鲜度 {freshness}%",
    "zh-Hant": "{coverage} 項評分輸入 · 數據質量 {quality}% · 新鮮度 {freshness}%",
  },
  "{coverage} scored inputs · {quality}% data quality": {
    "es": "{coverage} entradas puntuadas · {quality}% de calidad de datos",
    "zh-Hans": "{coverage} 项评分输入 · 数据质量 {quality}%",
    "zh-Hant": "{coverage} 項評分輸入 · 數據質量 {quality}%",
  },
  "Morning": {"es": "Buenos días", "zh-Hans": "早上好", "zh-Hant": "早上好"},
  "Afternoon": {"es": "Buenas tardes", "zh-Hans": "下午好", "zh-Hant": "下午好"},
  "Evening": {"es": "Buenas noches", "zh-Hans": "晚上好", "zh-Hant": "晚上好"},
  "Open profile": {
    "es": "Abrir perfil",
    "zh-Hans": "打开个人资料",
    "zh-Hant": "打開個人資料",
  },
  "{label} score": {
    "es": "Puntuación de {label}",
    "zh-Hans": "{label}评分",
    "zh-Hant": "{label}評分",
  },
  "{value} out of 100": {
    "es": "{value} de 100",
    "zh-Hans": "{value} 分（满分 100）",
    "zh-Hant": "{value} 分（滿分 100）",
  },
  "{label}: not enough information to estimate": {
    "es": "{label}: no hay información suficiente para estimar",
    "zh-Hans": "{label}：信息不足，无法估算",
    "zh-Hant": "{label}：信息不足，無法估算",
  },
  "Logged today": {
    "es": "Registrado hoy",
    "zh-Hans": "今天已记录",
    "zh-Hant": "今天已記錄",
  },
  "Not logged": {"es": "Sin registrar", "zh-Hans": "未记录", "zh-Hant": "未記錄"},
  "Sleep": {"es": "Sueño", "zh-Hans": "睡眠", "zh-Hant": "睡眠"},
  "Hydration": {"es": "Hidratación", "zh-Hans": "饮水", "zh-Hant": "飲水"},
  "Exercise": {"es": "Ejercicio", "zh-Hans": "运动", "zh-Hant": "運動"},
  "Steps": {"es": "Pasos", "zh-Hans": "步数", "zh-Hant": "步數"},
  "Study": {"es": "Estudio", "zh-Hans": "学习", "zh-Hant": "學習"},
  "Screen time": {
    "es": "Tiempo de pantalla",
    "zh-Hans": "屏幕时间",
    "zh-Hant": "屏幕時間",
  },
  "Reaction time": {
    "es": "Tiempo de reacción",
    "zh-Hans": "反应时间",
    "zh-Hant": "反應時間",
  },
  "Log today’s signals to personalize this estimate.": {
    "es": "Registra las señales de hoy para adaptar esta estimación.",
    "zh-Hans": "记录今天的信号以调整此估算。",
    "zh-Hant": "記錄今天的信號以調整此估算。",
  },
  "SUPPORTING": {"es": "A FAVOR", "zh-Hans": "支持因素", "zh-Hant": "支持因素"},
  "REDUCING": {"es": "EN CONTRA", "zh-Hans": "降低因素", "zh-Hant": "降低因素"},
  "NEUTRAL": {"es": "NEUTRO", "zh-Hans": "中性因素", "zh-Hant": "中性因素"},
  "{value} pts": {
    "es": "{value} pts",
    "zh-Hans": "{value} 分",
    "zh-Hant": "{value} 分",
  },
  "Recorded and demo sleep": {
    "es": "Sueño registrado y de demostración",
    "zh-Hans": "记录的睡眠和演示睡眠",
    "zh-Hant": "記錄的睡眠和演示睡眠",
  },
  "Demo sleep": {
    "es": "Sueño de demostración",
    "zh-Hans": "演示睡眠",
    "zh-Hant": "演示睡眠",
  },
  "Recorded sleep": {
    "es": "Sueño registrado",
    "zh-Hans": "记录的睡眠",
    "zh-Hant": "記錄的睡眠",
  },
  "These summaries include demo/synthetic examples, not imported or measured sleep. Totals, recent patterns and timing variation do not establish your personal sleep history.": {
    "es":
        "Estos resúmenes incluyen ejemplos de demostración o sintéticos, no sueño importado ni medido. Los totales, patrones recientes y variaciones horarias no establecen tu historial personal de sueño.",
    "zh-Hans": "这些摘要包含演示或合成示例，并非导入或测量的睡眠。总量、近期模式和时间变化不能代表你的个人睡眠历史。",
    "zh-Hant": "這些摘要包含演示或合成示例，並非導入或測量的睡眠。總量、近期模式和時間變化不能代表你的個人睡眠歷史。",
  },
  "No completed main sleep recorded.": {
    "es": "No hay un sueño principal completado registrado.",
    "zh-Hans": "尚未记录已完成的主要睡眠。",
    "zh-Hant": "尚未記錄已完成的主要睡眠。",
  },
  "Latest main sleep: {hours} h · {stamp} · {source}": {
    "es": "Último sueño principal: {hours} h · {stamp} · {source}",
    "zh-Hans": "最近的主要睡眠：{hours} 小时 · {stamp} · {source}",
    "zh-Hant": "最近的主要睡眠：{hours} 小時 · {stamp} · {source}",
  },
  "Demo / synthetic example": {
    "es": "Ejemplo de demostración / sintético",
    "zh-Hans": "演示／合成示例",
    "zh-Hant": "演示／合成示例",
  },
  "Apple Health estimate": {
    "es": "Estimación de Apple Salud",
    "zh-Hans": "Apple 健康估算",
    "zh-Hant": "Apple 健康估算",
  },
  "Manual entry": {
    "es": "Entrada manual",
    "zh-Hans": "手动记录",
    "zh-Hant": "手動記錄",
  },
  "Entered bed/wake times estimate sleep; they do not measure time asleep.": {
    "es":
        "Las horas de acostarse y despertarse permiten estimar el sueño; no miden el tiempo dormido.",
    "zh-Hans": "输入的就寝和起床时间仅用于估算睡眠，不能测量实际睡着的时长。",
    "zh-Hant": "輸入的就寢和起床時間僅用於估算睡眠，不能測量實際睡著的時長。",
  },
  "24-hour window: {start} → {end} (local time)": {
    "es": "Periodo de 24 horas: {start} → {end} (hora local)",
    "zh-Hans": "24 小时窗口：{start} → {end}（当地时间）",
    "zh-Hant": "24 小時窗口：{start} → {end}（當地時間）",
  },
  "Displayed sleep total": {
    "es": "Total de sueño mostrado",
    "zh-Hans": "显示的睡眠总量",
    "zh-Hant": "顯示的睡眠總量",
  },
  "Estimated recorded sleep": {
    "es": "Sueño registrado estimado",
    "zh-Hans": "估算的已记录睡眠",
    "zh-Hant": "估算的已記錄睡眠",
  },
  "{kind}: {total} h, including {naps} h in {count} naps.": {
    "es": "{kind}: {total} h, incluidas {naps} h en {count} siestas.",
    "zh-Hans": "{kind}：{total} 小时，其中 {count} 次小睡共 {naps} 小时。",
    "zh-Hant": "{kind}：{total} 小時，其中 {count} 次小睡共 {naps} 小時。",
  },
  "Overlaps are counted once. Naps are logged separately; their restorative effect is not treated as equivalent to main sleep.": {
    "es":
        "Los solapamientos se cuentan una sola vez. Las siestas se registran por separado; su efecto reparador no se considera equivalente al del sueño principal.",
    "zh-Hans": "重叠时间仅计一次。小睡单独记录，其恢复效果不视为等同于主要睡眠。",
    "zh-Hant": "重疊時間僅計一次。小睡單獨記錄，其恢復效果不視為等同於主要睡眠。",
  },
  "{count}/7 recent dates have a main-sleep record; {missing} dates are missing.": {
    "es":
        "{count}/7 fechas recientes tienen un registro de sueño principal; faltan {missing} fechas.",
    "zh-Hans": "最近 7 天中有 {count} 天记录了主要睡眠；缺少 {missing} 天。",
    "zh-Hant": "最近 7 天中有 {count} 天記錄了主要睡眠；缺少 {missing} 天。",
  },
  "Average in displayed records: {hours} h of main sleep.": {
    "es": "Promedio de los registros mostrados: {hours} h de sueño principal.",
    "zh-Hans": "显示记录中的平均主要睡眠：{hours} 小时。",
    "zh-Hant": "顯示記錄中的平均主要睡眠：{hours} 小時。",
  },
  "Usual in these records: {hours} h of main sleep. A personal pattern is not an age recommendation.": {
    "es":
        "Habitual en estos registros: {hours} h de sueño principal. Un patrón personal no es una recomendación por edad.",
    "zh-Hans": "这些记录中的通常主要睡眠：{hours} 小时。个人模式不是年龄建议。",
    "zh-Hant": "這些記錄中的通常主要睡眠：{hours} 小時。個人模式不是年齡建議。",
  },
  "Clock-time variation ({bedtimes} paired bedtimes, {wakes} wakes): bedtime {bed}; wake {wake}. Mean distance from usual clock time, not a health rating.": {
    "es":
        "Variación horaria ({bedtimes} horas de acostarse emparejadas, {wakes} despertares): acostarse {bed}; despertar {wake}. Distancia media de la hora habitual, no una valoración de salud.",
    "zh-Hans":
        "时刻变化（{bedtimes} 次配对就寝，{wakes} 次起床）：就寝 {bed}；起床 {wake}。这是与通常时刻的平均差距，不是健康评分。",
    "zh-Hant":
        "時刻變化（{bedtimes} 次配對就寢，{wakes} 次起床）：就寢 {bed}；起床 {wake}。這是與通常時刻的平均差距，不是健康評分。",
  },
  "not enough timing data": {
    "es": "faltan datos horarios",
    "zh-Hans": "时间数据不足",
    "zh-Hant": "時間數據不足",
  },
  "{value} min": {
    "es": "{value} min",
    "zh-Hans": "{value} 分钟",
    "zh-Hant": "{value} 分鐘",
  },
  "Recent observations": {
    "es": "Registros recientes",
    "zh-Hans": "近期观测",
    "zh-Hant": "近期觀測",
  },
  "Main sleep: {main} · Naps: {naps}": {
    "es": "Sueño principal: {main} · Siestas: {naps}",
    "zh-Hans": "主要睡眠：{main} · 小睡：{naps}",
    "zh-Hant": "主要睡眠：{main} · 小睡：{naps}",
  },
  "not recorded": {"es": "sin registrar", "zh-Hans": "未记录", "zh-Hant": "未記錄"},
  "AASM teen recommendation: 8–10 hours of sleep per 24 hours. This is separate from the experimental score.": {
    "es":
        "Recomendación de la AASM para adolescentes: 8–10 horas de sueño por cada 24 horas. Es independiente de la puntuación experimental.",
    "zh-Hans": "AASM 青少年建议：每 24 小时睡眠 8–10 小时。此建议与实验性评分独立。",
    "zh-Hant": "AASM 青少年建議：每 24 小時睡眠 8–10 小時。此建議與實驗性評分獨立。",
  },
  "I have recorded all sleep in this 24-hour window.": {
    "es": "He registrado todo el sueño de este periodo de 24 horas.",
    "zh-Hans": "我已记录此 24 小时窗口内的全部睡眠。",
    "zh-Hant": "我已記錄此 24 小時窗口內的全部睡眠。",
  },
  "This confirmation lasts only for this window and these records; it is not device-verified coverage.": {
    "es":
        "Esta confirmación solo es válida para este periodo y estos registros; el dispositivo no ha verificado la cobertura.",
    "zh-Hans": "此确认仅适用于此时间窗口和这些记录，并非设备验证的完整覆盖。",
    "zh-Hant": "此確認僅適用於此時間窗口和這些記錄，並非設備驗證的完整覆蓋。",
  },
  "Comparison unavailable: demo/synthetic examples cannot confirm your sleep coverage.": {
    "es":
        "Comparación no disponible: los ejemplos sintéticos o de demostración no confirman la cobertura de tu sueño.",
    "zh-Hans": "无法比较：演示或合成示例不能确认你的睡眠记录是否完整。",
    "zh-Hant": "無法比較：演示或合成示例不能確認你的睡眠記錄是否完整。",
  },
  "Comparison unavailable: sleep timing at the window boundary is incomplete.": {
    "es":
        "Comparación no disponible: falta información sobre el sueño en los límites del periodo.",
    "zh-Hans": "无法比较：窗口边界处的睡眠时间信息不完整。",
    "zh-Hant": "無法比較：窗口邊界處的睡眠時間信息不完整。",
  },
  "Comparison unavailable until complete sleep coverage is confirmed.": {
    "es":
        "La comparación no está disponible hasta confirmar que todo el sueño está registrado.",
    "zh-Hans": "确认睡眠记录完整之前无法比较。",
    "zh-Hant": "確認睡眠記錄完整之前無法比較。",
  },
  "The confirmed recorded total is below the teen range.": {
    "es":
        "El total registrado confirmado está por debajo del intervalo para adolescentes.",
    "zh-Hans": "已确认记录的总量低于青少年建议范围。",
    "zh-Hant": "已確認記錄的總量低於青少年建議範圍。",
  },
  "The confirmed recorded total is within the teen range. This does not establish recovery or readiness.": {
    "es":
        "El total registrado confirmado está dentro del intervalo para adolescentes. Esto no confirma la recuperación ni la preparación física.",
    "zh-Hans": "已确认记录的总量在青少年建议范围内。这不能证明已恢复或已准备就绪。",
    "zh-Hant": "已確認記錄的總量在青少年建議範圍內。這不能證明已恢復或已準備就緒。",
  },
  "The confirmed recorded total is above the teen range. More hours do not earn more score points.": {
    "es":
        "El total registrado confirmado supera el intervalo para adolescentes. Más horas no suman más puntos.",
    "zh-Hans": "已确认记录的总量高于青少年建议范围。更多睡眠时间不会获得更多加分。",
    "zh-Hant": "已確認記錄的總量高於青少年建議範圍。更多睡眠時間不會獲得更多加分。",
  },
  "No age-specific comparison is available for this age band.": {
    "es": "No hay comparación específica disponible para este grupo de edad.",
    "zh-Hans": "此年龄组暂无年龄特定的比较。",
    "zh-Hant": "此年齡組暫無年齡特定的比較。",
  },
  "Your personal baselines": {
    "es": "Tus referencias personales",
    "zh-Hans": "你的个人基线",
    "zh-Hant": "你的個人基線",
  },
  "{ready}/4 established · {days}-day private history": {
    "es": "{ready}/4 establecidas · historial privado de {days} días",
    "zh-Hans": "已建立 {ready}/4 项 · {days} 天私有历史",
    "zh-Hant": "已建立 {ready}/4 項 · {days} 天私有歷史",
  },
  "These are usual patterns in your records, not healthy targets or age recommendations. Data quality stays limited while a baseline is building.": {
    "es":
        "Son patrones habituales de tus registros, no objetivos de salud ni recomendaciones por edad. La calidad de los datos es limitada mientras se establece una referencia.",
    "zh-Hans": "这些是记录中的通常模式，不是健康目标或年龄建议。基线建立期间的数据质量仍有限。",
    "zh-Hant": "這些是記錄中的通常模式，不是健康目標或年齡建議。基線建立期間的數據質量仍有限。",
  },
  "AI Coach": {"es": "Asistente de IA", "zh-Hans": "AI 指导", "zh-Hant": "AI 指導"},
  "Refresh guidance": {
    "es": "Actualizar orientación",
    "zh-Hans": "刷新指导",
    "zh-Hant": "刷新指導",
  },
  "Recorded patterns": {
    "es": "Patrones registrados",
    "zh-Hans": "已记录的模式",
    "zh-Hant": "已記錄的模式",
  },
  "Today’s plan": {"es": "Plan de hoy", "zh-Hans": "今日计划", "zh-Hant": "今日計劃"},
  "Guidance is based on your recent Tonyo entries and is for general wellness only. It does not diagnose a medical condition. If symptoms are severe, unusual, or persistent, talk with a qualified clinician.": {
    "es":
        "La orientación se basa en tus registros recientes de Tonyo y solo busca el bienestar general. No diagnostica enfermedades. Si los síntomas son graves, inusuales o persistentes, consulta a un profesional sanitario cualificado.",
    "zh-Hans": "指导基于你近期的 Tonyo 记录，仅用于一般健康管理，不用于诊断疾病。如果症状严重、异常或持续，请咨询合格的临床专业人员。",
    "zh-Hant": "指導基於你近期的 Tonyo 記錄，僅用於一般健康管理，不用於診斷疾病。如果症狀嚴重、異常或持續，請咨詢合格的臨床專業人員。",
  },
  "Optional blocks around your saved wake and bed times": {
    "es":
        "Bloques opcionales según tus horas guardadas de despertar y acostarte",
    "zh-Hans": "根据已保存的起床和就寝时间提供可选安排",
    "zh-Hant": "根據已保存的起床和就寢時間提供可選安排",
  },
  "Private guidance saved to your account": {
    "es": "Orientación privada guardada en tu cuenta",
    "zh-Hans": "私人指导已保存到你的账户",
    "zh-Hant": "私人指導已保存到你的賬戶",
  },
  "Calculated privately on this device": {
    "es": "Calculado de forma privada en este dispositivo",
    "zh-Hans": "在此设备上私密计算",
    "zh-Hant": "在此設備上私密計算",
  },
  "Generated daily plan": {
    "es": "Plan diario generado",
    "zh-Hans": "已生成的每日计划",
    "zh-Hant": "已生成的每日計劃",
  },
  "{blocks} plan blocks · {flags} active flags": {
    "es": "{blocks} bloques del plan · {flags} avisos activos",
    "zh-Hans": "{blocks} 个计划安排 · {flags} 项有效提示",
    "zh-Hant": "{blocks} 個計劃安排 · {flags} 項有效提示",
  },
  "{blocks} plan blocks · {flags} active flag": {
    "es": "{blocks} bloques del plan · {flags} aviso activo",
    "zh-Hans": "{blocks} 个计划安排 · {flags} 项有效提示",
    "zh-Hant": "{blocks} 個計劃安排 · {flags} 項有效提示",
  },
  "Waiting for enough current information": {
    "es": "Esperando información actual suficiente",
    "zh-Hans": "等待足够的当前信息",
    "zh-Hant": "等待足夠的當前信息",
  },
  "Morning-to-evening plan · {range}": {
    "es": "Plan de mañana a noche · {range}",
    "zh-Hans": "从早到晚的计划 · {range}",
    "zh-Hant": "從早到晚的計劃 · {range}",
  },
  "{value}% DATA COVERAGE": {
    "es": "{value}% DE COBERTURA DE DATOS",
    "zh-Hans": "数据覆盖率 {value}%",
    "zh-Hant": "數據覆蓋率 {value}%",
  },
  "{count} PAST RESPONSES": {
    "es": "{count} RESPUESTAS ANTERIORES",
    "zh-Hans": "{count} 条历史反馈",
    "zh-Hant": "{count} 條歷史反饋",
  },
  "These are optional scheduling suggestions, not validated predictions of your best times.": {
    "es":
        "Son sugerencias horarias opcionales, no predicciones validadas de tus mejores horas.",
    "zh-Hans": "这些是可选的时间安排建议，不是经过验证的最佳时段预测。",
    "zh-Hant": "這些是可選的時間安排建議，不是經過驗證的最佳時段預測。",
  },
  "Your feedback helps prioritize future advice. Today’s blocks stay in time order.": {
    "es":
        "Tus comentarios ayudan a priorizar los consejos futuros. Los bloques de hoy siguen en orden horario.",
    "zh-Hans": "你的反馈有助于确定今后建议的优先顺序。今日安排仍按时间排序。",
    "zh-Hant": "你的反饋有助於確定今後建議的優先順序。今日安排仍按時間排序。",
  },
  "Could not update reminders. Please try again.": {
    "es": "No se pudieron actualizar los recordatorios. Inténtalo de nuevo.",
    "zh-Hans": "无法更新提醒，请重试。",
    "zh-Hant": "無法更新提醒，請重試。",
  },
  "Scheduled reminders are unavailable on this device.": {
    "es": "Este dispositivo no admite recordatorios programados.",
    "zh-Hans": "此设备无法使用定时提醒。",
    "zh-Hant": "此設備無法使用定時提醒。",
  },
  "Updating today’s reminders…": {
    "es": "Actualizando los recordatorios de hoy…",
    "zh-Hans": "正在更新今日提醒…",
    "zh-Hant": "正在更新今日提醒…",
  },
  "Daily plan reminders are off.": {
    "es": "Los recordatorios del plan diario están desactivados.",
    "zh-Hans": "每日计划提醒已关闭。",
    "zh-Hant": "每日計劃提醒已關閉。",
  },
  "Notifications are off. Enable them to receive your plan reminders.": {
    "es":
        "Las notificaciones están desactivadas. Actívalas para recibir los recordatorios del plan.",
    "zh-Hans": "通知已关闭。开启通知以接收计划提醒。",
    "zh-Hant": "通知已關閉。開啓通知以接收計劃提醒。",
  },
  "No upcoming plan reminders are scheduled.": {
    "es": "No hay próximos recordatorios del plan programados.",
    "zh-Hans": "未安排即将到来的计划提醒。",
    "zh-Hant": "未安排即將到來的計劃提醒。",
  },
  "{count} reminders scheduled for today.": {
    "es": "{count} recordatorios programados para hoy.",
    "zh-Hans": "今天已安排 {count} 条提醒。",
    "zh-Hant": "今天已安排 {count} 條提醒。",
  },
  "{count} reminder scheduled for today.": {
    "es": "{count} recordatorio programado para hoy.",
    "zh-Hans": "今天已安排 {count} 条提醒。",
    "zh-Hant": "今天已安排 {count} 條提醒。",
  },
  "Daily plan reminders": {
    "es": "Recordatorios del plan diario",
    "zh-Hans": "每日计划提醒",
    "zh-Hant": "每日計劃提醒",
  },
  "A notification when each upcoming plan block starts.": {
    "es": "Una notificación al comenzar cada próximo bloque del plan.",
    "zh-Hans": "在每个即将到来的计划安排开始时发送通知。",
    "zh-Hant": "在每個即將到來的計劃安排開始時發送通知。",
  },
  "Enable notifications": {
    "es": "Activar notificaciones",
    "zh-Hans": "开启通知",
    "zh-Hant": "開啓通知",
  },
  "Open Tonyo each day to refresh your plan and schedule today’s reminders. Permission is requested when you turn reminders on. Experimental, uncalibrated forecasts do not trigger alerts.": {
    "es":
        "Abre Tonyo cada día para actualizar tu plan y programar los recordatorios de hoy. Se pide permiso al activar los recordatorios. Los pronósticos experimentales sin calibrar no generan alertas.",
    "zh-Hans": "每天打开 Tonyo 以刷新计划并安排今日提醒。开启提醒时会请求权限。未经校准的实验性预测不会触发警报。",
    "zh-Hant": "每天打開 Tonyo 以刷新計劃並安排今日提醒。開啓提醒時會請求權限。未經校准的實驗性預測不會觸發警報。",
  },
  "No recorded pattern to show": {
    "es": "No hay patrones registrados para mostrar",
    "zh-Hans": "暂无可显示的已记录模式",
    "zh-Hant": "暫無可顯示的已記錄模式",
  },
  "This does not establish recovery or rule out a health concern. Missing entries limit what Tonyo can describe.": {
    "es":
        "Esto no confirma la recuperación ni descarta un problema de salud. La falta de registros limita lo que Tonyo puede describir.",
    "zh-Hans": "这不能证明已恢复，也不能排除健康问题。缺失记录会限制 Tonyo 可描述的内容。",
    "zh-Hant": "這不能證明已恢復，也不能排除健康問題。缺失記錄會限制 Tonyo 可描述的內容。",
  },
  "Dismiss": {"es": "Descartar", "zh-Hans": "关闭", "zh-Hant": "關閉"},
  "Add recent entries to build your plan": {
    "es": "Añade registros recientes para crear tu plan",
    "zh-Hans": "添加近期记录以生成计划",
    "zh-Hant": "添加近期記錄以生成計劃",
  },
  "Not enough information to estimate. Optional schedule suggestions require current supporting observations.": {
    "es":
        "No hay información suficiente para estimar. Las sugerencias horarias opcionales requieren observaciones actuales que las respalden.",
    "zh-Hans": "信息不足，无法估算。可选时间安排建议需要当前观测记录的支持。",
    "zh-Hant": "信息不足，無法估算。可選時間安排建議需要當前觀測記錄的支持。",
  },
  "PRIORITY": {"es": "PRIORIDAD", "zh-Hans": "优先", "zh-Hant": "優先"},
  "OPTIONAL SCHEDULE": {
    "es": "HORARIO OPCIONAL",
    "zh-Hans": "可选时间安排",
    "zh-Hant": "可選時間安排",
  },
  "{duration} MIN": {
    "es": "{duration} MIN",
    "zh-Hans": "{duration} 分钟",
    "zh-Hant": "{duration} 分鐘",
  },
  "Was this advice helpful? (optional)": {
    "es": "¿Te resultó útil este consejo? (opcional)",
    "zh-Hans": "这条建议有帮助吗？（可选）",
    "zh-Hant": "這條建議有幫助嗎？（可選）",
  },
  "Helpful · saved": {
    "es": "Útil · guardado",
    "zh-Hans": "有帮助 · 已保存",
    "zh-Hant": "有幫助 · 已保存",
  },
  "Helpful": {"es": "Útil", "zh-Hans": "有帮助", "zh-Hant": "有幫助"},
  "Not helpful · saved": {
    "es": "No es útil · guardado",
    "zh-Hans": "无帮助 · 已保存",
    "zh-Hant": "無幫助 · 已保存",
  },
  "Not helpful": {"es": "No es útil", "zh-Hans": "无帮助", "zh-Hant": "無幫助"},
  "Time passed": {"es": "Hora pasada", "zh-Hans": "时间已过", "zh-Hant": "時間已過"},
  "Reminders unavailable on this device": {
    "es": "Recordatorios no disponibles en este dispositivo",
    "zh-Hans": "此设备无法使用提醒",
    "zh-Hant": "此設備無法使用提醒",
  },
  "Reminders off": {
    "es": "Recordatorios desactivados",
    "zh-Hans": "提醒已关闭",
    "zh-Hant": "提醒已關閉",
  },
  "Updating reminder…": {
    "es": "Actualizando recordatorio…",
    "zh-Hans": "正在更新提醒…",
    "zh-Hant": "正在更新提醒…",
  },
  "Reminder not scheduled · check reminder settings": {
    "es": "Recordatorio sin programar · revisa los ajustes",
    "zh-Hans": "未安排提醒 · 请检查提醒设置",
    "zh-Hant": "未安排提醒 · 請檢查提醒設置",
  },
  "Reminder scheduled · {time}": {
    "es": "Recordatorio programado · {time}",
    "zh-Hans": "已安排提醒 · {time}",
    "zh-Hant": "已安排提醒 · {time}",
  },
  "No reminder scheduled": {
    "es": "Sin recordatorio programado",
    "zh-Hans": "未安排提醒",
    "zh-Hant": "未安排提醒",
  },
  "Linked to recent private data": {
    "es": "Vinculado a datos privados recientes",
    "zh-Hans": "关联近期私人数据",
    "zh-Hant": "關聯近期私人數據",
  },
  "+{count} more": {
    "es": "+{count} más",
    "zh-Hans": "另有 {count} 项",
    "zh-Hant": "另有 {count} 項",
  },
  "Could not save this change. Please try again.": {
    "es": "No se pudo guardar el cambio. Inténtalo de nuevo.",
    "zh-Hans": "无法保存此更改，请重试。",
    "zh-Hant": "無法保存此更改，請重試。",
  },
  "Recorded patterns and experimental estimates": {
    "es": "Patrones registrados y estimaciones experimentales",
    "zh-Hans": "已记录的模式和实验性估算",
    "zh-Hant": "已記錄的模式和實驗性估算",
  },
  "Refresh insights": {
    "es": "Actualizar tendencias",
    "zh-Hans": "刷新数据洞察",
    "zh-Hant": "刷新數據洞察",
  },
  "7-day overview": {
    "es": "Resumen de 7 días",
    "zh-Hans": "7 天概览",
    "zh-Hant": "7 天概覽",
  },
  "Daily trends": {
    "es": "Tendencias diarias",
    "zh-Hans": "每日趋势",
    "zh-Hant": "每日趨勢",
  },
  "Model associations": {
    "es": "Asociaciones del modelo",
    "zh-Hans": "模型关联",
    "zh-Hant": "模型關聯",
  },
  "Today’s experimental estimates": {
    "es": "Estimaciones experimentales de hoy",
    "zh-Hans": "今日实验性估算",
    "zh-Hant": "今日實驗性估算",
  },
  "Daily Score Models": {
    "es": "Modelos de puntuación diaria",
    "zh-Hans": "每日评分模型",
    "zh-Hant": "每日評分模型",
  },
  "Ranked inputs · data coverage and quality": {
    "es": "Entradas ordenadas · cobertura y calidad de datos",
    "zh-Hans": "输入排序 · 数据覆盖与质量",
    "zh-Hant": "輸入排序 · 數據覆蓋與質量",
  },
  "Personal baselines": {
    "es": "Referencias personales",
    "zh-Hans": "个人基线",
    "zh-Hant": "個人基線",
  },
  "Today’s Energy drivers": {
    "es": "Factores de energía de hoy",
    "zh-Hans": "今日精力影响因素",
    "zh-Hant": "今日精力影響因素",
  },
  "Today’s Cognitive drivers": {
    "es": "Factores cognitivos de hoy",
    "zh-Hans": "今日认知影响因素",
    "zh-Hant": "今日認知影響因素",
  },
  "Not enough current information to estimate Energy. An optional check-in can add an observation.": {
    "es":
        "No hay información actual suficiente para estimar la energía. Una autoevaluación opcional puede añadir un registro.",
    "zh-Hans": "当前信息不足，无法估算精力。可选自评可以添加一条观测记录。",
    "zh-Hant": "當前信息不足，無法估算精力。可選自評可以添加一條觀測記錄。",
  },
  "Not enough current information to estimate the experimental Cognitive score.": {
    "es":
        "No hay información actual suficiente para estimar la puntuación cognitiva experimental.",
    "zh-Hans": "当前信息不足，无法估算实验性认知评分。",
    "zh-Hant": "當前信息不足，無法估算實驗性認知評分。",
  },
  "{count} current Cognitive inputs · data quality": {
    "es": "{count} entradas cognitivas actuales · calidad de datos",
    "zh-Hans": "{count} 项当前认知输入 · 数据质量",
    "zh-Hant": "{count} 項當前認知輸入 · 數據質量",
  },
  "Data quality describes the coverage, age, source, and quality of records. It is not the probability that a score is correct. These experimental rules are not medical findings or proof of cause.": {
    "es":
        "La calidad de los datos describe la cobertura, antigüedad, fuente y calidad de los registros. No es la probabilidad de que la puntuación sea correcta. Estas reglas experimentales no son hallazgos médicos ni pruebas de causalidad.",
    "zh-Hans": "数据质量描述记录的覆盖程度、时间、来源和质量，并非评分正确的概率。这些实验性规则不是医学发现，也不能证明因果关系。",
    "zh-Hant": "數據質量描述記錄的覆蓋程度、時間、來源和質量，並非評分正確的概率。這些實驗性規則不是醫學發現，也不能證明因果關係。",
  },
  "Your private Firestore range": {
    "es": "Tu intervalo privado de Firestore",
    "zh-Hans": "你的私人 Firestore 数据范围",
    "zh-Hant": "你的私人 Firestore 數據範圍",
  },
  "Your on-device entries": {
    "es": "Tus registros en este dispositivo",
    "zh-Hans": "此设备上的记录",
    "zh-Hant": "此設備上的記錄",
  },
  "{signals} signals · {checkins} check-ins · no cohort comparisons": {
    "es":
        "{signals} señales · {checkins} autoevaluaciones · sin comparaciones con otros grupos",
    "zh-Hans": "{signals} 个信号 · {checkins} 次自评 · 不进行人群比较",
    "zh-Hant": "{signals} 個信號 · {checkins} 次自評 · 不進行人群比較",
  },
  "Recomputed experimental estimates · current deterministic rules ({energy}; {cognitive}). No learned personalization. Past days use end-of-day observations; today uses entries up to now. Available earlier records form each day’s personal baseline. Missing history can change these estimates; they are not the scores originally shown on those dates.": {
    "es":
        "Estimaciones experimentales recalculadas · reglas deterministas actuales ({energy}; {cognitive}). Sin personalización aprendida. Los días pasados usan registros al final del día; hoy usa los disponibles hasta ahora. Los registros anteriores disponibles forman la referencia personal de cada día. El historial ausente puede cambiar estas estimaciones; no son las puntuaciones mostradas originalmente en esas fechas.",
    "zh-Hans":
        "重新计算的实验性估算 · 当前确定性规则（{energy}；{cognitive}）。无学习型个性化。过去日期使用日末观测；今天使用截至当前的记录。现有较早记录形成每天的个人基线。历史缺失可能改变估算；这些并非当时显示的原始评分。",
    "zh-Hant":
        "重新計算的實驗性估算 · 當前確定性規則（{energy}；{cognitive}）。無學習型個性化。過去日期使用日末觀測；今天使用截至當前的記錄。現有較早記錄形成每天的個人基線。歷史缺失可能改變估算；這些並非當時顯示的原始評分。",
  },
  "Not enough recent entries yet": {
    "es": "Aún faltan registros recientes",
    "zh-Hans": "近期记录仍不足",
    "zh-Hant": "近期記錄仍不足",
  },
  "Log sleep, training, or study to build your private seven-day trends.": {
    "es":
        "Registra sueño, entrenamiento o estudio para crear tus tendencias privadas de siete días.",
    "zh-Hans": "记录睡眠、训练或学习以建立你的私人七日趋势。",
    "zh-Hant": "記錄睡眠、訓練或學習以建立你的私人七日趨勢。",
  },
  "Avg main sleep": {
    "es": "Sueño principal medio",
    "zh-Hans": "平均主要睡眠",
    "zh-Hant": "平均主要睡眠",
  },
  "Training": {"es": "Entrenamiento", "zh-Hans": "训练", "zh-Hant": "訓練"},
  "Avg energy": {"es": "Energía media", "zh-Hans": "平均精力", "zh-Hant": "平均精力"},
  "{tracked}/7 days have entries; {sleep} main-sleep observations; {energy} eligible Energy estimates. Averages use recorded days only. Comparisons use the prior seven days.": {
    "es":
        "{tracked}/7 días tienen registros; {sleep} observaciones de sueño principal; {energy} estimaciones de energía con datos suficientes. Los promedios usan solo los días registrados. Las comparaciones usan los siete días anteriores.",
    "zh-Hans":
        "7 天中有 {tracked} 天有记录；{sleep} 条主要睡眠观测；{energy} 项符合条件的精力估算。平均值仅基于有记录的日期。比较基于之前七天。",
    "zh-Hant":
        "7 天中有 {tracked} 天有記錄；{sleep} 條主要睡眠觀測；{energy} 項符合條件的精力估算。平均值僅基於有記錄的日期。比較基於之前七天。",
  },
  "No prior comparison": {
    "es": "Sin comparación anterior",
    "zh-Hans": "暂无以往比较",
    "zh-Hant": "暫無以往比較",
  },
  "About even vs prior 7d": {
    "es": "Similar a los 7 días anteriores",
    "zh-Hans": "与之前 7 天基本相同",
    "zh-Hant": "與之前 7 天基本相同",
  },
  "{value} vs prior 7d": {
    "es": "{value} frente a los 7 días anteriores",
    "zh-Hans": "较之前 7 天：{value}",
    "zh-Hant": "較之前 7 天：{value}",
  },
  "Swipe to view more days.": {
    "es": "Desliza para ver más días.",
    "zh-Hans": "滑动以查看更多日期。",
    "zh-Hant": "滑動以查看更多日期。",
  },
  "Daily Energy values use the current deterministic rules, without learned personalization. Experimental recomputations are not measurements; days without current supporting inputs stay blank.": {
    "es":
        "Los valores diarios de energía usan las reglas deterministas actuales, sin personalización aprendida. Los recálculos experimentales no son mediciones; los días sin datos actuales de apoyo quedan en blanco.",
    "zh-Hans": "每日精力值使用当前确定性规则，不含学习型个性化。实验性重算不是测量；缺乏当日支持输入的日期保持空白。",
    "zh-Hant": "每日精力值使用當前確定性規則，不含學習型個性化。實驗性重算不是測量；缺乏當日支持輸入的日期保持空白。",
  },
  "Latest main sleep for each day; naps are tracked separately and missing days remain blank.": {
    "es":
        "Último sueño principal de cada día; las siestas se registran aparte y los días sin datos quedan en blanco.",
    "zh-Hans": "每天最近一次主要睡眠；小睡单独跟踪，缺失日期保持空白。",
    "zh-Hant": "每天最近一次主要睡眠；小睡單獨跟蹤，缺失日期保持空白。",
  },
  "Daily total of your exercise entries; missing days are not treated as zero.": {
    "es":
        "Total diario de tus registros de ejercicio; los días sin datos no se consideran cero.",
    "zh-Hans": "每日运动记录总量；缺失日期不视为零。",
    "zh-Hant": "每日運動記錄總量；缺失日期不視為零。",
  },
  "Daily total of your study entries; missing days are not treated as zero.": {
    "es":
        "Total diario de tus registros de estudio; los días sin datos no se consideran cero.",
    "zh-Hans": "每日学习记录总量；缺失日期不视为零。",
    "zh-Hant": "每日學習記錄總量；缺失日期不視為零。",
  },
  "Mon": {"es": "Lun", "zh-Hans": "周一", "zh-Hant": "週一"},
  "Tue": {"es": "Mar", "zh-Hans": "周二", "zh-Hant": "週二"},
  "Wed": {"es": "Mié", "zh-Hans": "周三", "zh-Hant": "週三"},
  "Thu": {"es": "Jue", "zh-Hans": "周四", "zh-Hant": "週四"},
  "Fri": {"es": "Vie", "zh-Hans": "周五", "zh-Hant": "週五"},
  "Sat": {"es": "Sáb", "zh-Hans": "周六", "zh-Hant": "週六"},
  "Sun": {"es": "Dom", "zh-Hans": "周日", "zh-Hant": "周日"},
  "These compare entries with a score partly calculated from those same entries. They describe the current rules, not an independent health outcome or evidence that a behavior helps.": {
    "es":
        "Comparan los registros con una puntuación calculada en parte a partir de esos mismos registros. Describen las reglas actuales, no un resultado de salud independiente ni pruebas de que una conducta ayude.",
    "zh-Hans": "这些比较将记录与部分基于同样记录计算的评分关联起来。它们描述当前规则，并非独立的健康结果，也不是某种行为有益的证据。",
    "zh-Hant": "這些比較將記錄與部分基於同樣記錄計算的評分關聯起來。它們描述當前規則，並非獨立的健康結果，也不是某種行為有益的證據。",
  },
  "At least three matched days with varied sleep, training, or study entries are needed for an association summary.": {
    "es":
        "Se necesitan al menos tres días coincidentes con registros variados de sueño, entrenamiento o estudio para resumir una asociación.",
    "zh-Hans": "关联摘要至少需要三个对应日期，且睡眠、训练或学习记录有所变化。",
    "zh-Hant": "關聯摘要至少需要三個對應日期，且睡眠、訓練或學習記錄有所變化。",
  },
  "{title} data quality": {
    "es": "Calidad de datos de {title}",
    "zh-Hans": "{title}数据质量",
    "zh-Hant": "{title}數據質量",
  },
  "Unavailable": {"es": "No disponible", "zh-Hans": "不可用", "zh-Hant": "不可用"},
  "{value}% coverage": {
    "es": "{value}% de cobertura",
    "zh-Hans": "覆盖率 {value}%",
    "zh-Hant": "覆蓋率 {value}%",
  },
  "freshness unavailable": {
    "es": "actualidad no disponible",
    "zh-Hans": "新鲜度不可用",
    "zh-Hant": "新鮮度不可用",
  },
  "{value}% fresh": {
    "es": "{value}% de actualidad",
    "zh-Hans": "新鲜度 {value}%",
    "zh-Hant": "新鮮度 {value}%",
  },
  "SUPPORTING TODAY": {
    "es": "A FAVOR HOY",
    "zh-Hans": "今日支持因素",
    "zh-Hant": "今日支持因素",
  },
  "REDUCING TODAY": {
    "es": "EN CONTRA HOY",
    "zh-Hans": "今日降低因素",
    "zh-Hant": "今日降低因素",
  },
  "Manual": {"es": "Manual", "zh-Hans": "手动", "zh-Hant": "手動"},
  "Model": {"es": "Modelo", "zh-Hans": "模型", "zh-Hant": "模型"},
  "Legacy snapshot": {
    "es": "Resumen antiguo",
    "zh-Hans": "旧版快照",
    "zh-Hant": "舊版快照",
  },
  "Check-in": {"es": "Autoevaluación", "zh-Hans": "自评", "zh-Hant": "自評"},
  "Yesterday": {"es": "Ayer", "zh-Hans": "昨天", "zh-Hant": "昨天"},
  "{count} days ago": {
    "es": "hace {count} días",
    "zh-Hans": "{count} 天前",
    "zh-Hant": "{count} 天前",
  },
  "{title}: Not enough information to estimate.": {
    "es": "{title}: no hay información suficiente para estimar.",
    "zh-Hans": "{title}：信息不足，无法估算。",
    "zh-Hant": "{title}：信息不足，無法估算。",
  },
  "{title} experimental estimate: {score} out of 100. {quality}% data quality, not probability of correctness. {coverage}. {age}.": {
    "es":
        "Estimación experimental de {title}: {score} de 100. {quality}% de calidad de datos, no probabilidad de exactitud. {coverage}. {age}.",
    "zh-Hans":
        "{title}实验性估算：{score} 分（满分 100）。数据质量 {quality}%，不是正确概率。{coverage}。{age}。",
    "zh-Hant":
        "{title}實驗性估算：{score} 分（滿分 100）。數據質量 {quality}%，不是正確概率。{coverage}。{age}。",
  },
  "{value} out of 100, estimated": {
    "es": "{value} de 100, estimado",
    "zh-Hans": "估算 {value} 分（满分 100）",
    "zh-Hant": "估算 {value} 分（滿分 100）",
  },
};
