// Oura connection and source-specific metrics. Provider and method names stay
// identifiable; private source metadata is never sent to a translation service.
const ouraTranslations = <String, Map<String, String>>{
  'Oura': {'es': 'Oura', 'zh-Hans': 'Oura', 'zh-Hant': 'Oura'},
  'Oura heart metrics': {
    'es': 'Métricas cardíacas de Oura',
    'zh-Hans': 'Oura 心脏指标',
    'zh-Hant': 'Oura 心臟指標',
  },
  'Nighttime HRV and resting heart rate': {
    'es': 'VFC nocturna y frecuencia cardíaca en reposo',
    'zh-Hans': '夜间心率变异性和静息心率',
    'zh-Hant': '夜間心率變異性和靜息心率',
  },
  'Connect Oura to import your nighttime HRV and resting heart rate from the last 30 days. You choose whether to allow access in Oura.': {
    'es':
        'Conecta Oura para importar tu VFC nocturna y frecuencia cardíaca en reposo de los últimos 30 días. Tú eliges si permites el acceso en Oura.',
    'zh-Hans': '连接 Oura，导入过去 30 天的夜间心率变异性和静息心率。是否允许访问由你在 Oura 中决定。',
    'zh-Hant': '連接 Oura，匯入過去 30 天的夜間心率變異性和靜息心率。是否允許存取由你在 Oura 中決定。',
  },
  'Apple Health can stay connected. Oura and Apple Health measurements are shown separately because their measurement methods differ.': {
    'es':
        'Apple Salud puede seguir conectado. Las mediciones de Oura y Apple Salud se muestran por separado porque usan métodos distintos.',
    'zh-Hans': 'Apple 健康可以保持连接。Oura 和 Apple 健康的测量方法不同，因此数据会分别显示。',
    'zh-Hant': 'Apple 健康可以保持連接。Oura 和 Apple 健康的測量方法不同，因此資料會分別顯示。',
  },
  'After connecting, Tonyo checks for updates when you open the app and every 15 minutes while it is open. Sync your ring in Oura first.': {
    'es':
        'Después de conectar, Tonyo busca actualizaciones al abrir la app y cada 15 minutos mientras permanece abierta. Primero sincroniza tu anillo en Oura.',
    'zh-Hans': '连接后，Tonyo 会在打开应用时检查更新，并在应用打开期间每 15 分钟检查一次。请先在 Oura 中同步戒指。',
    'zh-Hant': '連接後，Tonyo 會在開啟應用程式時檢查更新，並在應用程式開啟期間每 15 分鐘檢查一次。請先在 Oura 中同步戒指。',
  },
  'Imported readings are saved in Tonyo and included in your private account sync. Disconnecting stops future imports and keeps saved readings. Clear tracking history to remove them.': {
    'es':
        'Las lecturas importadas se guardan en Tonyo y se sincronizan con tu cuenta privada. Desconectar detiene futuras importaciones y conserva las lecturas guardadas. Borra el historial de seguimiento para eliminarlas.',
    'zh-Hans':
        '导入的读数会保存在 Tonyo 中，并同步到你的私人账户。断开连接会停止后续导入，但保留已保存的读数。清除跟踪历史可删除这些读数。',
    'zh-Hant':
        '匯入的讀數會儲存在 Tonyo 中，並同步到你的私人帳戶。中斷連接會停止後續匯入，但保留已儲存的讀數。清除追蹤歷史可刪除這些讀數。',
  },
  'Connect Oura': {
    'es': 'Conectar Oura',
    'zh-Hans': '连接 Oura',
    'zh-Hant': '連接 Oura',
  },
  'Disconnect Oura': {
    'es': 'Desconectar Oura',
    'zh-Hans': '断开 Oura 连接',
    'zh-Hant': '中斷 Oura 連接',
  },
  'Retry disconnect': {
    'es': 'Reintentar desconexión',
    'zh-Hans': '重试断开连接',
    'zh-Hant': '重試中斷連接',
  },
  'Connecting…': {'es': 'Conectando…', 'zh-Hans': '正在连接…', 'zh-Hant': '正在連接…'},
  'Syncing…': {'es': 'Sincronizando…', 'zh-Hans': '正在同步…', 'zh-Hant': '正在同步…'},
  'Last synced: {time}': {
    'es': 'Última sincronización: {time}',
    'zh-Hans': '上次同步：{time}',
    'zh-Hant': '上次同步：{time}',
  },
  'Oura connection was cancelled.': {
    'es': 'Se canceló la conexión con Oura.',
    'zh-Hans': '已取消连接 Oura。',
    'zh-Hant': '已取消連接 Oura。',
  },
  'Oura connection is not available in this build yet.': {
    'es': 'La conexión con Oura aún no está disponible en esta versión.',
    'zh-Hans': '此版本尚不支持连接 Oura。',
    'zh-Hant': '此版本尚不支援連接 Oura。',
  },
  'Sign in to your Tonyo account to connect Oura.': {
    'es': 'Inicia sesión en tu cuenta de Tonyo para conectar Oura.',
    'zh-Hans': '登录你的 Tonyo 账户以连接 Oura。',
    'zh-Hant': '登入你的 Tonyo 帳戶以連接 Oura。',
  },
  'Review your privacy choices before connecting Oura.': {
    'es': 'Revisa tus opciones de privacidad antes de conectar Oura.',
    'zh-Hans': '连接 Oura 前，请检查你的隐私选项。',
    'zh-Hant': '連接 Oura 前，請檢查你的隱私選項。',
  },
  'Reconnect Oura to resume syncing.': {
    'es': 'Vuelve a conectar Oura para reanudar la sincronización.',
    'zh-Hans': '重新连接 Oura 以恢复同步。',
    'zh-Hant': '重新連接 Oura 以恢復同步。',
  },
  'Oura is already syncing. Try again shortly.': {
    'es':
        'Oura ya se está sincronizando. Vuelve a intentarlo en unos momentos.',
    'zh-Hans': 'Oura 正在同步。请稍后重试。',
    'zh-Hant': 'Oura 正在同步。請稍後重試。',
  },
  'Oura could not finish syncing. Please retry.': {
    'es': 'Oura no pudo completar la sincronización. Vuelve a intentarlo.',
    'zh-Hans': 'Oura 未能完成同步。请重试。',
    'zh-Hant': 'Oura 未能完成同步。請重試。',
  },
  'Oura sync is paused. Retry disconnect to finish.': {
    'es':
        'La sincronización con Oura está en pausa. Reintenta la desconexión para terminar.',
    'zh-Hans': 'Oura 同步已暂停。请重试断开连接以完成操作。',
    'zh-Hant': 'Oura 同步已暫停。請重試中斷連接以完成操作。',
  },
  'Oura nightly measurements stay separate from Apple Health. Oura uses its original sleep date.': {
    'es':
        'Las mediciones nocturnas de Oura se mantienen separadas de Apple Salud. Oura usa la fecha original del sueño.',
    'zh-Hans': 'Oura 夜间测量数据与 Apple 健康数据分开显示。Oura 使用原始睡眠日期。',
    'zh-Hant': 'Oura 夜間測量資料與 Apple 健康資料分開顯示。Oura 使用原始睡眠日期。',
  },
  'Oura nightly measurements': {
    'es': 'Mediciones nocturnas de Oura',
    'zh-Hans': 'Oura 夜间测量数据',
    'zh-Hant': 'Oura 夜間測量資料',
  },
  'Oura HRV (RMSSD)': {
    'es': 'VFC de Oura (RMSSD)',
    'zh-Hans': 'Oura 心率变异性（RMSSD）',
    'zh-Hant': 'Oura 心率變異性（RMSSD）',
  },
  'Oura lowest sleeping heart rate (API)': {
    'es': 'Frecuencia cardíaca mínima durante el sueño de Oura (API)',
    'zh-Hans': 'Oura 最低睡眠心率（API）',
    'zh-Hant': 'Oura 最低睡眠心率（API）',
  },
  'Oura resting heart rate (nightly minimum)': {
    'es': 'Frecuencia cardíaca en reposo de Oura (mínimo nocturno)',
    'zh-Hans': 'Oura 静息心率（夜间最低值）',
    'zh-Hant': 'Oura 靜息心率（夜間最低值）',
  },
  'Oura nighttime RMSSD and Apple Health SDNN use different HRV calculations. Their values are not averaged together.': {
    'es':
        'El RMSSD nocturno de Oura y el SDNN de Apple Salud usan cálculos de VFC distintos. Sus valores no se promedian juntos.',
    'zh-Hans': 'Oura 的夜间 RMSSD 和 Apple 健康的 SDNN 使用不同的心率变异性计算方法，两者不会合并求平均值。',
    'zh-Hant': 'Oura 的夜間 RMSSD 和 Apple 健康的 SDNN 使用不同的心率變異性計算方法，兩者不會合併計算平均值。',
  },
  'Five-minute samples were unavailable. This API minimum may differ from the resting heart rate shown in Oura.': {
    'es':
        'No había muestras de cinco minutos disponibles. Este mínimo de la API puede diferir de la frecuencia cardíaca en reposo mostrada en Oura.',
    'zh-Hans': '没有可用的五分钟采样数据。此 API 最低值可能与 Oura 中显示的静息心率不同。',
    'zh-Hant': '沒有可用的五分鐘取樣資料。此 API 最低值可能與 Oura 中顯示的靜息心率不同。',
  },
};
