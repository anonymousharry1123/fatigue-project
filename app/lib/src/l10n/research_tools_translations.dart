/// Authored presentation copy; exports retain the original questionnaire text.
const Map<String, Map<String, String>> researchToolsTranslations = {
  'Private response table and data dictionary': {
    'es': 'Tabla privada de respuestas y diccionario de datos',
    'zh-Hans': '私密回答表与数据字典',
    'zh-Hant': '私密回答表與資料字典',
  },
  'Instrument availability and review requirements': {
    'es': 'Disponibilidad de instrumentos y requisitos de revisión',
    'zh-Hans': '测量工具可用状态与审核要求',
    'zh-Hant': '測量工具可用狀態與審查要求',
  },
  'Research export': {
    'es': 'Exportación para investigación',
    'zh-Hans': '研究数据导出',
    'zh-Hant': '研究資料匯出',
  },
  'A private measurement table': {
    'es': 'Una tabla privada de mediciones',
    'zh-Hans': '私密测量数据表',
    'zh-Hant': '私密測量資料表',
  },
  'Export saved device check-ins, including partial answers and pending edits. Names, account IDs and notes are excluded. Dates and wellness records remain sensitive; this is not anonymous data.': {
    'es':
        'Exporta los registros guardados en el dispositivo, incluidas las respuestas parciales y las modificaciones pendientes. Se excluyen los nombres, los identificadores de cuenta y las notas. Las fechas y los registros de bienestar siguen siendo sensibles; estos datos no son anónimos.',
    'zh-Hans':
        '导出设备上保存的自评，包括未全部回答的记录和待同步的修改。导出内容不含姓名、账户 ID 和备注。日期与健康记录仍属于敏感信息，并非匿名数据。',
    'zh-Hant':
        '匯出裝置上儲存的自評，包括未全部回答的記錄和待同步的修改。匯出內容不含姓名、帳號 ID 和備註。日期與健康記錄仍屬於敏感資訊，並非匿名資料。',
  },
  'Use a study code, not your name or email. Keep any identity key separately. Nothing is uploaded by this export.': {
    'es':
        'Usa un código de estudio, no tu nombre ni tu correo electrónico. Guarda por separado cualquier clave que vincule el código con tu identidad. Esta exportación no sube ningún dato.',
    'zh-Hans': '请使用研究代号，不要使用姓名或电子邮箱。请单独保存代号与身份的对应表。本次导出不会上传任何数据。',
    'zh-Hant': '請使用研究代碼，不要使用姓名或電子郵件地址。請另行保存代碼與身分的對照表。本次匯出不會上傳任何資料。',
  },
  'Study code': {
    'es': 'Código de estudio',
    'zh-Hans': '研究代号',
    'zh-Hant': '研究代碼',
  },
  'Prepare research export': {
    'es': 'Preparar exportación para investigación',
    'zh-Hans': '准备研究数据导出',
    'zh-Hant': '準備研究資料匯出',
  },
  'Device data is unavailable for this account.': {
    'es': 'Los datos del dispositivo no están disponibles para esta cuenta.',
    'zh-Hans': '此账户无法使用设备上的数据。',
    'zh-Hant': '此帳號無法使用裝置上的資料。',
  },
  '{rows} responses · {partial} partial · {pairs} sleep pairs · {excluded} excluded': {
    'es':
        '{rows} respuestas · {partial} parciales · {pairs} pares de sueño · {excluded} excluidos',
    'zh-Hans':
        '{rows} 份回答 · {partial} 份未全部回答 · {pairs} 组睡眠匹配 · {excluded} 条已排除',
    'zh-Hant':
        '{rows} 份回答 · {partial} 份未全部回答 · {pairs} 組睡眠配對 · {excluded} 筆已排除',
  },
  'JSON includes the data dictionary, exact questionnaire definitions and sleep provenance. CSV contains the response table; empty cells mean missing.': {
    'es':
        'El archivo JSON incluye el diccionario de datos, las definiciones exactas del cuestionario y la procedencia de los datos de sueño. El CSV contiene la tabla de respuestas; las celdas vacías indican datos ausentes.',
    'zh-Hans': 'JSON 包含数据字典、完整原样的问卷定义和睡眠数据来源。CSV 包含回答表；空白单元格表示数据缺失。',
    'zh-Hant': 'JSON 包含資料字典、完整原樣的問卷定義和睡眠資料來源。CSV 包含回答表；空白儲存格表示資料缺漏。',
  },
  'Sleep pairs are descriptive matches using records available now, not approved research joins or prediction features. Repeated submissions remain separate rows.': {
    'es':
        'Los pares de sueño son emparejamientos descriptivos basados en los registros disponibles ahora; no son vínculos aprobados para investigación ni variables predictoras. Las entregas repetidas se mantienen en filas separadas.',
    'zh-Hans': '睡眠匹配仅根据当前可用记录进行描述性配对，并非经批准的研究数据关联或预测特征。重复提交的记录仍各占一行。',
    'zh-Hant': '睡眠配對僅根據目前可用記錄進行描述性配對，並非經核准的研究資料關聯或預測特徵。重複提交的記錄仍各占一列。',
  },
  'This prepared snapshot does not update automatically. Prepare again to include later changes.': {
    'es':
        'Esta copia preparada no se actualiza automáticamente. Vuelve a prepararla para incluir los cambios posteriores.',
    'zh-Hans': '已准备的数据快照不会自动更新。请重新准备，以包含后续修改。',
    'zh-Hant': '已準備的資料快照不會自動更新。請重新準備，以包含後續修改。',
  },
  'Save research JSON': {
    'es': 'Guardar JSON de investigación',
    'zh-Hans': '保存研究 JSON',
    'zh-Hant': '儲存研究 JSON',
  },
  'Copy research CSV': {
    'es': 'Copiar CSV de investigación',
    'zh-Hans': '复制研究 CSV',
    'zh-Hant': '複製研究 CSV',
  },
  'Copy research JSON': {
    'es': 'Copiar JSON de investigación',
    'zh-Hans': '复制研究 JSON',
    'zh-Hant': '複製研究 JSON',
  },
  'Use a study code of 1–32 letters, numbers, - or _, starting with a letter.': {
    'es':
        'Usa un código de estudio de 1 a 32 caracteres: letras, números, - o _. Debe empezar por una letra.',
    'zh-Hans': '研究代号须以字母开头，长度为 1–32 个字符，仅可包含字母、数字、- 或 _。',
    'zh-Hant': '研究代碼須以字母開頭，長度為 1–32 個字元，僅可包含字母、數字、- 或 _。',
  },
  'Could not prepare the research export. Please try again.': {
    'es':
        'No se pudo preparar la exportación para investigación. Inténtalo de nuevo.',
    'zh-Hans': '无法准备研究数据导出，请重试。',
    'zh-Hant': '無法準備研究資料匯出，請重試。',
  },
  'Research JSON saved.': {
    'es': 'JSON de investigación guardado.',
    'zh-Hans': '研究 JSON 已保存。',
    'zh-Hant': '研究 JSON 已儲存。',
  },
  'Export canceled. No file was saved.': {
    'es': 'Exportación cancelada. No se guardó ningún archivo.',
    'zh-Hans': '导出已取消，未保存文件。',
    'zh-Hant': '匯出已取消，未儲存檔案。',
  },
  'Could not save the research export. Retry or use Copy JSON.': {
    'es':
        'No se pudo guardar la exportación para investigación. Inténtalo de nuevo o copia el JSON.',
    'zh-Hans': '无法保存研究数据导出。请重试或使用“复制研究 JSON”。',
    'zh-Hant': '無法儲存研究資料匯出。請重試或使用「複製研究 JSON」。',
  },
  'Copy sensitive research data?': {
    'es': '¿Copiar datos sensibles de investigación?',
    'zh-Hans': '复制敏感研究数据？',
    'zh-Hant': '複製敏感研究資料？',
  },
  'Other apps may read your clipboard. Copy only when you are ready to paste into a private file.': {
    'es':
        'Otras aplicaciones pueden leer el portapapeles. Copia los datos solo cuando vayas a pegarlos en un archivo privado.',
    'zh-Hans': '其他应用可能读取剪贴板。请在准备好将数据粘贴到私密文件时再复制。',
    'zh-Hant': '其他應用程式可能讀取剪貼簿。請在準備好將資料貼到私密檔案時再複製。',
  },
  'Copy': {'es': 'Copiar', 'zh-Hans': '复制', 'zh-Hant': '複製'},
  'Research data copied. Paste into a private file.': {
    'es': 'Datos de investigación copiados. Pégalos en un archivo privado.',
    'zh-Hans': '研究数据已复制，请粘贴到私密文件中。',
    'zh-Hant': '研究資料已複製，請貼到私密檔案中。',
  },
  'Could not copy the research data. Please try again.': {
    'es':
        'No se pudieron copiar los datos de investigación. Inténtalo de nuevo.',
    'zh-Hans': '无法复制研究数据，请重试。',
    'zh-Hant': '無法複製研究資料，請重試。',
  },
  'Questionnaire library': {
    'es': 'Biblioteca de cuestionarios',
    'zh-Hans': '问卷库',
    'zh-Hant': '問卷庫',
  },
  'No periodic questionnaire is available': {
    'es': 'No hay cuestionarios periódicos disponibles',
    'zh-Hans': '暂无可用的定期问卷',
    'zh-Hant': '暫無可用的定期問卷',
  },
  'Installed instruments: {count}': {
    'es': 'Instrumentos instalados: {count}',
    'zh-Hans': '已安装的测量工具：{count}',
    'zh-Hant': '已安裝的測量工具：{count}',
  },
  'No published questionnaire has been selected or approved for Tonyo.': {
    'es':
        'No se ha seleccionado ni aprobado ningún cuestionario publicado para Tonyo.',
    'zh-Hans': '尚未为 Tonyo 选定或批准任何已发表的问卷。',
    'zh-Hant': '尚未為 Tonyo 選定或核准任何已發表的問卷。',
  },
  'Before an instrument can be added': {
    'es': 'Antes de añadir un instrumento',
    'zh-Hans': '添加测量工具前的要求',
    'zh-Hant': '新增測量工具前的要求',
  },
  'An instrument needs documented review of its intended age group, language, recall period, permissions for digital use and scoring instructions.': {
    'es':
        'El instrumento requiere una revisión documentada de su grupo de edad previsto, idioma, periodo de recuerdo, permisos de uso digital e instrucciones de puntuación.',
    'zh-Hans': '测量工具需要有书面审核记录，涵盖适用年龄、语言、回顾时间范围、数字使用许可和计分说明。',
    'zh-Hant': '測量工具需要有書面審查記錄，涵蓋適用年齡、語言、回顧時間範圍、數位使用許可和計分說明。',
  },
  'Biological, youth-appropriateness and software reviews are separate. An app screen or software test does not establish clinical validation.': {
    'es':
        'Las revisiones biológica, de adecuación para menores y de software son independientes. Una pantalla de la aplicación o una prueba de software no demuestran validación clínica.',
    'zh-Hans': '生物学依据、未成年人适用性和软件实现须分别审核。应用界面或软件测试不能证明临床有效性。',
    'zh-Hant': '生物學依據、未成年人適用性和軟體實作須分別審查。應用程式介面或軟體測試不能證明臨床效度。',
  },
  'Any future collection also needs the applicable privacy, consent and research approvals.': {
    'es':
        'Cualquier recopilación futura también requiere las autorizaciones correspondientes de privacidad, consentimiento e investigación.',
    'zh-Hans': '未来开展任何数据收集，还须满足适用的隐私、同意和研究审批要求。',
    'zh-Hant': '未來進行任何資料蒐集，還須滿足適用的隱私、同意和研究審查核准要求。',
  },
  'Daily check-ins stay separate': {
    'es': 'Los registros diarios se mantienen por separado',
    'zh-Hans': '每日自评保持独立',
    'zh-Hant': '每日自評保持獨立',
  },
  'Tonyo’s daily 1–10 questions remain custom research check-ins in draft form, not a clinical assessment. Their original answers are not converted into questionnaire scores.': {
    'es':
        'Las preguntas diarias de Tonyo del 1 al 10 siguen siendo registros de investigación personalizados en borrador, no una evaluación clínica. Sus respuestas originales no se convierten en puntuaciones de cuestionarios.',
    'zh-Hans': 'Tonyo 每日 1–10 分问题仍是自定义研究自评草案，并非临床评估。原始回答不会转换为问卷分数。',
    'zh-Hant': 'Tonyo 每日 1–10 分問題仍是自訂研究自評草案，並非臨床評估。原始回答不會轉換為問卷分數。',
  },
};
