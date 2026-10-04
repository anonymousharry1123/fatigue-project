/// Forecast presentation copy. Stored observations and engine values stay unchanged.
const Map<String, Map<String, String>> forecastTranslations = {
  "Energy Forecast": {
    "es": "Previsión de energía",
    "zh-Hans": "精力预测",
    "zh-Hant": "精力預測",
  },
  "Refresh forecast": {
    "es": "Actualizar previsión",
    "zh-Hans": "刷新预测",
    "zh-Hant": "重新整理預測",
  },
  "Experimental hourly curve from recorded inputs and fixed timing rules.": {
    "es":
        "Curva horaria experimental basada en datos registrados y reglas horarias fijas.",
    "zh-Hans": "根据已记录的输入和固定时间规则生成的实验性小时曲线。",
    "zh-Hant": "根據已記錄的輸入和固定時間規則產生的實驗性小時曲線。",
  },
  "Today": {"es": "Hoy", "zh-Hans": "今天", "zh-Hant": "今天"},
  "Tomorrow": {"es": "Mañana", "zh-Hans": "明天", "zh-Hant": "明天"},
  "Week": {"es": "Semana", "zh-Hans": "一周", "zh-Hant": "一週"},
  "Using on-device forecast": {
    "es": "Usando la previsión del dispositivo",
    "zh-Hans": "正在使用设备上的预测",
    "zh-Hant": "正在使用裝置上的預測",
  },
  "The curve and shaded bands are uncalibrated estimates, not statistical confidence intervals. They do not establish when you will feel alert or tired, or whether exercise is safe.": {
    "es":
        "La curva y las bandas sombreadas son estimaciones sin calibrar, no intervalos de confianza estadísticos. No determinan cuándo te sentirás alerta o cansado, ni si es seguro hacer ejercicio.",
    "zh-Hans": "曲线和阴影带是未经校准的估计，并非统计置信区间。它们不能确定你何时会清醒或疲倦，也不能判断运动是否安全。",
    "zh-Hant": "曲線和陰影帶是未經校準的估計，並非統計信賴區間。它們無法確定你何時會清醒或疲倦，也無法判斷運動是否安全。",
  },
  "Private saved forecast": {
    "es": "Previsión guardada de forma privada",
    "zh-Hans": "私密保存的预测",
    "zh-Hant": "私密儲存的預測",
  },
  "Calculated and saved privately": {
    "es": "Calculado y guardado de forma privada",
    "zh-Hans": "已私密计算并保存",
    "zh-Hant": "已私密計算並儲存",
  },
  "Calculated on this device": {
    "es": "Calculado en este dispositivo",
    "zh-Hans": "在此设备上计算",
    "zh-Hant": "在此裝置上計算",
  },
  "Forecast is out of date": {
    "es": "La previsión está desactualizada",
    "zh-Hans": "预测已过时",
    "zh-Hant": "預測已過時",
  },
  "Refresh to check whether current entries support a curve.": {
    "es":
        "Actualiza para comprobar si los registros actuales permiten generar una curva.",
    "zh-Hans": "刷新以检查当前记录是否足以生成曲线。",
    "zh-Hant": "重新整理以檢查目前記錄是否足以產生曲線。",
  },
  "Limited data quality": {
    "es": "Calidad de datos limitada",
    "zh-Hans": "数据质量有限",
    "zh-Hant": "資料品質有限",
  },
  "The displayed band averages ±{points} points. This width is a rule-based display estimate, not a calibrated error range.": {
    "es":
        "La banda mostrada tiene una media de ±{points} puntos. Su anchura es una estimación visual basada en reglas, no un margen de error calibrado.",
    "zh-Hans": "显示带的平均宽度为 ±{points} 分。这是基于规则的显示估计，并非经过校准的误差范围。",
    "zh-Hant": "顯示帶的平均寬度為 ±{points} 分。這是基於規則的顯示估計，並非經過校準的誤差範圍。",
  },
  "Curve high {time}": {
    "es": "Máximo de la curva {time}",
    "zh-Hans": "曲线高点 {time}",
    "zh-Hant": "曲線高點 {time}",
  },
  "Average {value}": {
    "es": "Media {value}",
    "zh-Hans": "平均 {value}",
    "zh-Hant": "平均 {value}",
  },
  "{low}–{high} range": {
    "es": "Rango {low}–{high}",
    "zh-Hans": "范围 {low}–{high}",
    "zh-Hant": "範圍 {low}–{high}",
  },
  "±{points} uncalibrated band": {
    "es": "Banda sin calibrar de ±{points}",
    "zh-Hans": "未经校准的范围 ±{points}",
    "zh-Hant": "未經校準的範圍 ±{points}",
  },
  "Curve markers": {
    "es": "Marcadores de la curva",
    "zh-Hans": "曲线标记",
    "zh-Hant": "曲線標記",
  },
  "These markers describe the formula’s curve. Their timing is not a validated prediction of focus, a crash, or recovery.": {
    "es":
        "Estos marcadores describen la curva de la fórmula. Sus horarios no son predicciones validadas de concentración, bajón o recuperación.",
    "zh-Hans": "这些标记描述公式的曲线，其时间并非经过验证的专注、精力骤降或恢复预测。",
    "zh-Hant": "這些標記描述公式的曲線，其時間並非經過驗證的專注、精力驟降或恢復預測。",
  },
  "What shapes this curve": {
    "es": "Qué determina esta curva",
    "zh-Hans": "曲线的依据",
    "zh-Hant": "曲線的依據",
  },
  "Recorded sleep timing": {
    "es": "Horarios de sueño registrados",
    "zh-Hans": "已记录的睡眠时间",
    "zh-Hant": "已記錄的睡眠時間",
  },
  "Recent wake/bed observations and your saved schedule adjust timing; they do not measure recovery.": {
    "es":
        "Las observaciones recientes de sueño y tu horario guardado ajustan los tiempos; no miden la recuperación.",
    "zh-Hans": "近期入睡和起床记录及已保存的作息会调整曲线时间，但并不衡量恢复状况。",
    "zh-Hant": "近期入睡和起床記錄及已儲存的作息會調整曲線時間，但並不衡量恢復狀況。",
  },
  "Fixed clock-time curve": {
    "es": "Curva de horarios fijos",
    "zh-Hans": "固定时钟时间曲线",
    "zh-Hant": "固定時鐘時間曲線",
  },
  "An assumed daily shape, not a measurement of your internal circadian phase.": {
    "es":
        "Es una forma diaria supuesta, no una medición de tu fase circadiana interna.",
    "zh-Hans": "这是预设的日间形状，并非对你内在昼夜节律相位的测量。",
    "zh-Hant": "這是預設的日間形狀，並非對你內在晝夜節律相位的測量。",
  },
  "Experimental Energy reference": {
    "es": "Referencia experimental de energía",
    "zh-Hans": "实验性精力参考",
    "zh-Hant": "實驗性精力參考",
  },
  "Current scored inputs and fixed forecast adjustments. Caffeine, fluid volume and exercise duration add no recovery rewards.": {
    "es":
        "Datos actuales puntuados y ajustes fijos de previsión. La cafeína, el volumen de líquidos y la duración del ejercicio no otorgan puntos de recuperación.",
    "zh-Hans": "使用当前计分输入和固定预测调整。咖啡因、饮水量和运动时长不会增加恢复奖励分。",
    "zh-Hant": "使用目前計分輸入和固定預測調整。咖啡因、飲水量和運動時長不會增加恢復獎勵分。",
  },
  "Curve high": {
    "es": "Máximo de la curva",
    "zh-Hans": "曲线高点",
    "zh-Hant": "曲線高點",
  },
  "Curve low": {
    "es": "Mínimo de la curva",
    "zh-Hans": "曲线低点",
    "zh-Hant": "曲線低點",
  },
  "Later curve rise": {
    "es": "Subida posterior de la curva",
    "zh-Hans": "曲线后段上升",
    "zh-Hant": "曲線後段上升",
  },
  "No linked signal or check-in documents available.": {
    "es": "No hay señales ni registros vinculados disponibles.",
    "zh-Hans": "没有可关联的信号或自评记录。",
    "zh-Hant": "沒有可關聯的訊號或自評記錄。",
  },
  "LINKED EVIDENCE": {
    "es": "DATOS VINCULADOS",
    "zh-Hans": "关联依据",
    "zh-Hant": "關聯依據",
  },
  "Linked signal": {
    "es": "Señal vinculada",
    "zh-Hans": "关联信号",
    "zh-Hant": "關聯訊號",
  },
  "Linked check-in": {
    "es": "Registro vinculado",
    "zh-Hans": "关联自评",
    "zh-Hant": "關聯自評",
  },
  "Model": {"es": "Modelo", "zh-Hans": "模型", "zh-Hant": "模型"},
  "Manual": {"es": "Manual", "zh-Hans": "手动", "zh-Hant": "手動"},
  "Demo / synthetic example": {
    "es": "Demostración / ejemplo sintético",
    "zh-Hans": "演示／合成示例",
    "zh-Hant": "示範／合成範例",
  },
  "{source} · {date} at {time}": {
    "es": "{source} · {date} a las {time}",
    "zh-Hans": "{source} · {date} {time}",
    "zh-Hant": "{source} · {date} {time}",
  },
  "{kind} document {id}": {
    "es": "Documento de {kind}: {id}",
    "zh-Hans": "{kind}文档 {id}",
    "zh-Hant": "{kind}文件 {id}",
  },
  "Partial weekly forecast": {
    "es": "Previsión semanal parcial",
    "zh-Hans": "部分周预测",
    "zh-Hant": "部分週預測",
  },
  "{available} of {total} days are available. Refresh to fill the missing days.": {
    "es":
        "Hay {available} de {total} días disponibles. Actualiza para completar los días restantes.",
    "zh-Hans": "已提供 {total} 天中的 {available} 天。刷新以补充缺失日期。",
    "zh-Hant": "已提供 {total} 天中的 {available} 天。重新整理以補充缺失日期。",
  },
  "7-DAY OUTLOOK": {
    "es": "VISTA DE 7 DÍAS",
    "zh-Hans": "7 天展望",
    "zh-Hant": "7 天展望",
  },
  "All displayed bands are uncalibrated estimates.": {
    "es": "Todas las bandas mostradas son estimaciones sin calibrar.",
    "zh-Hans": "所有显示范围均为未经校准的估计。",
    "zh-Hant": "所有顯示範圍均為未經校準的估計。",
  },
  "{days} day has a wider uncalibrated band.": {
    "es": "{days} día tiene una banda sin calibrar más amplia.",
    "zh-Hans": "{days} 天的未经校准范围较宽。",
    "zh-Hant": "{days} 天的未經校準範圍較寬。",
  },
  "{days} days have a wider uncalibrated band.": {
    "es": "{days} días tienen una banda sin calibrar más amplia.",
    "zh-Hans": "{days} 天的未经校准范围较宽。",
    "zh-Hant": "{days} 天的未經校準範圍較寬。",
  },
  "Daily summaries": {
    "es": "Resúmenes diarios",
    "zh-Hans": "每日摘要",
    "zh-Hant": "每日摘要",
  },
  "Curve high {value} at {time}": {
    "es": "Máximo de la curva {value} a las {time}",
    "zh-Hans": "曲线高点 {value}，时间 {time}",
    "zh-Hant": "曲線高點 {value}，時間 {time}",
  },
  "Average estimated Energy": {
    "es": "Energía estimada media",
    "zh-Hans": "平均估计精力",
    "zh-Hant": "平均估計精力",
  },
  "{value} out of 100": {
    "es": "{value} de 100",
    "zh-Hans": "{value}／100",
    "zh-Hant": "{value}／100",
  },
  "{date}. Average estimated Energy: {value} out of 100. Uncalibrated display band: plus or minus {points} points; not a statistical confidence interval.": {
    "es":
        "{date}. Energía estimada media: {value} de 100. Banda visual sin calibrar: más o menos {points} puntos; no es un intervalo de confianza estadístico.",
    "zh-Hans": "{date}。平均估计精力：{value}／100。未经校准的显示范围：正负 {points} 分；并非统计置信区间。",
    "zh-Hant": "{date}。平均估計精力：{value}／100。未經校準的顯示範圍：正負 {points} 分；並非統計信賴區間。",
  },
  "Swipe to view more days.": {
    "es": "Desliza para ver más días.",
    "zh-Hans": "滑动查看更多日期。",
    "zh-Hant": "滑動查看更多日期。",
  },
  "Building your forecast…": {
    "es": "Creando tu previsión…",
    "zh-Hans": "正在生成预测…",
    "zh-Hant": "正在產生預測…",
  },
  "No forecast available": {
    "es": "No hay previsión disponible",
    "zh-Hans": "暂无预测",
    "zh-Hant": "暫無預測",
  },
  "Combining your recent signals and check-ins.": {
    "es": "Combinando tus señales y registros recientes.",
    "zh-Hans": "正在整合近期信号和自评记录。",
    "zh-Hant": "正在整合近期訊號和自評記錄。",
  },
  "Not enough current information to estimate this range. An optional check-in can add an observation.": {
    "es":
        "No hay suficientes datos actuales para estimar este periodo. Un registro opcional puede aportar una observación.",
    "zh-Hans": "当前信息不足以估计此时间范围。你可以选择填写自评，增加一条观察记录。",
    "zh-Hant": "目前資訊不足以估計此時間範圍。你可以選擇填寫自評，增加一筆觀察記錄。",
  },
  "Build forecast": {
    "es": "Crear previsión",
    "zh-Hans": "生成预测",
    "zh-Hant": "產生預測",
  },
  "TODAY": {"es": "HOY", "zh-Hans": "今天", "zh-Hant": "今天"},
  "TOMORROW": {"es": "MAÑANA", "zh-Hans": "明天", "zh-Hant": "明天"},
  "Mon": {"es": "Lun", "zh-Hans": "周一", "zh-Hant": "週一"},
  "Tue": {"es": "Mar", "zh-Hans": "周二", "zh-Hant": "週二"},
  "Wed": {"es": "Mié", "zh-Hans": "周三", "zh-Hant": "週三"},
  "Thu": {"es": "Jue", "zh-Hans": "周四", "zh-Hant": "週四"},
  "Fri": {"es": "Vie", "zh-Hans": "周五", "zh-Hant": "週五"},
  "Sat": {"es": "Sáb", "zh-Hans": "周六", "zh-Hant": "週六"},
  "Sun": {"es": "Dom", "zh-Hans": "周日", "zh-Hant": "週日"},
  "Update time unavailable": {
    "es": "Hora de actualización no disponible",
    "zh-Hans": "更新时间不可用",
    "zh-Hant": "更新時間無法取得",
  },
  "Updated just now": {
    "es": "Actualizado ahora",
    "zh-Hans": "刚刚更新",
    "zh-Hant": "剛剛更新",
  },
  "Updated {minutes}m ago": {
    "es": "Actualizado hace {minutes} min",
    "zh-Hans": "{minutes} 分钟前更新",
    "zh-Hant": "{minutes} 分鐘前更新",
  },
  "Updated {hours}h ago": {
    "es": "Actualizado hace {hours} h",
    "zh-Hans": "{hours} 小时前更新",
    "zh-Hant": "{hours} 小時前更新",
  },
  "Updated {days}d ago": {
    "es": "Actualizado hace {days} días",
    "zh-Hans": "{days} 天前更新",
    "zh-Hant": "{days} 天前更新",
  },
  "{first} and {second}": {
    "es": "{first} y {second}",
    "zh-Hans": "{first}和{second}",
    "zh-Hant": "{first}和{second}",
  },
  "Experimental higher point in the curve, using {inputs}. Timing is unvalidated.": {
    "es":
        "Punto alto experimental de la curva basado en {inputs}. Su horario no está validado.",
    "zh-Hans": "根据{inputs}得出的实验性曲线高点。时间未经验证。",
    "zh-Hant": "根據{inputs}得出的實驗性曲線高點。時間未經驗證。",
  },
  "Experimental lower point in the curve, using {inputs}. A crash is not established.": {
    "es":
        "Punto bajo experimental de la curva basado en {inputs}. No demuestra un bajón.",
    "zh-Hans": "根据{inputs}得出的实验性曲线低点。不能据此确定精力骤降。",
    "zh-Hant": "根據{inputs}得出的實驗性曲線低點。無法據此確定精力驟降。",
  },
  "Experimental later rise in the curve, using {inputs}. Recovery is not established.": {
    "es":
        "Subida posterior experimental de la curva basada en {inputs}. No demuestra recuperación.",
    "zh-Hans": "根据{inputs}得出的实验性曲线后段上升。不能据此确定恢复。",
    "zh-Hant": "根據{inputs}得出的實驗性曲線後段上升。無法據此確定恢復。",
  },
  "Uncalibrated experimental curve; no linked observations were saved.": {
    "es":
        "Curva experimental sin calibrar; no se guardaron observaciones vinculadas.",
    "zh-Hans": "未经校准的实验性曲线；未保存关联的观察记录。",
    "zh-Hant": "未經校準的實驗性曲線；未儲存關聯的觀察記錄。",
  },
  "Sleep": {"es": "Sueño", "zh-Hans": "睡眠", "zh-Hant": "睡眠"},
  "Bedtime": {"es": "Hora de acostarse", "zh-Hans": "就寝时间", "zh-Hant": "就寢時間"},
  "Study": {"es": "Estudio", "zh-Hans": "学习", "zh-Hant": "學習"},
  "Morning check-in": {
    "es": "Registro de la mañana",
    "zh-Hans": "上午自评",
    "zh-Hant": "上午自評",
  },
  "Afternoon check-in": {
    "es": "Registro de la tarde",
    "zh-Hans": "下午自评",
    "zh-Hant": "下午自評",
  },
  "Evening check-in": {
    "es": "Registro de la noche",
    "zh-Hans": "晚间自评",
    "zh-Hant": "晚間自評",
  },
  "Energy {energy}/10 · mood {mood}/10 · stress {stress}/10": {
    "es": "Energía {energy}/10 · ánimo {mood}/10 · estrés {stress}/10",
    "zh-Hans": "精力 {energy}/10 · 心情 {mood}/10 · 压力 {stress}/10",
    "zh-Hant": "精力 {energy}/10 · 心情 {mood}/10 · 壓力 {stress}/10",
  },
  "Main-sleep completion at {time}; timing only in this curve": {
    "es":
        "Sueño principal terminado a las {time}; solo ajusta el horario de esta curva",
    "zh-Hans": "主睡眠结束于 {time}；在此曲线中仅用于时间调整",
    "zh-Hant": "主睡眠結束於 {time}；在此曲線中僅用於時間調整",
  },
  "Bedtime {time}": {
    "es": "Hora de acostarse {time}",
    "zh-Hans": "就寝时间 {time}",
    "zh-Hant": "就寢時間 {time}",
  },
  "{hours} hr study load": {
    "es": "{hours} h de estudio",
    "zh-Hans": "学习量 {hours} 小时",
    "zh-Hant": "學習量 {hours} 小時",
  },
  "{minutes} min nap": {
    "es": "Siesta de {minutes} min",
    "zh-Hans": "小睡 {minutes} 分钟",
    "zh-Hant": "小睡 {minutes} 分鐘",
  },
  "{litres} L logged": {
    "es": "{litres} L registrados",
    "zh-Hans": "已记录 {litres} 升",
    "zh-Hant": "已記錄 {litres} 公升",
  },
  "{hours} hr exercise": {
    "es": "{hours} h de ejercicio",
    "zh-Hans": "运动 {hours} 小时",
    "zh-Hant": "運動 {hours} 小時",
  },
};
