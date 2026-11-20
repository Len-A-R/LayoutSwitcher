object FormMain: TFormMain
  Left = 0
  Top = 0
  BorderIcons = [biSystemMenu]
  BorderStyle = bsSingle
  Caption = 'LayoutSwitcher - '#1055#1077#1088#1077#1082#1083#1102#1095#1072#1090#1077#1083#1100' '#1088#1072#1089#1082#1083#1072#1076#1086#1082' '#1082#1083#1072#1074#1080#1072#1090#1091#1088#1099
  ClientHeight = 453
  ClientWidth = 540
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  Position = poScreenCenter
  OnCloseQuery = FormCloseQuery
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  TextHeight = 13
  object lblVersion: TLabel
    Left = 8
    Top = 426
    Width = 8
    Height = 13
    Caption = #1042#1077#1088#1089#1080#1103
    Font.Charset = DEFAULT_CHARSET
    Font.Color = cl3DDkShadow
    Font.Height = -11
    Font.Name = 'Tahoma'
    Font.Style = []
    ParentFont = False
  end
  object lblAuthor: TLabel
    Left = 120
    Top = 426
    Width = 8
    Height = 13
    Caption = 'len-a-r'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = cl3DDkShadow
    Font.Height = -11
    Font.Name = 'Tahoma'
    Font.Style = []
    ParentFont = False
  end
  object pcMain: TPageControl
    Left = 8
    Top = 8
    Width = 524
    Height = 404
    ActivePage = tsGeneral
    TabOrder = 0
    object tsGeneral: TTabSheet
      Caption = #1054#1089#1085#1086#1074#1085#1099#1077
      object chkAutorun: TCheckBox
        Left = 12
        Top = 12
        Width = 480
        Height = 17
        Caption = #1040#1074#1090#1086#1079#1072#1087#1091#1089#1082' '#1087#1088#1080' '#1089#1090#1072#1088#1090#1077' '#1089#1080#1089#1090#1077#1084#1099
        TabOrder = 0
        OnClick = chkAutorunClick
      end
      object chkAutorunElevated: TCheckBox
        Left = 30
        Top = 34
        Width = 470
        Height = 17
        Caption = #1047#1072#1087#1091#1089#1082#1072#1090#1100' '#1089' '#1087#1088#1072#1074#1072#1084#1080' '#1072#1076#1084#1080#1085#1080#1089#1090#1088#1072#1090#1086#1088#1072' ('#1076#1083#1103' '#1086#1082#1086#1085', '#1086#1090#1082#1088#1099#1090#1099#1093' '#1086#1090' '#1080#1084#1077#1085#1080' '#1072#1076#1084#1080#1085#1080#1089#1090#1088#1072#1090#1086#1088#1072')'
        TabOrder = 1
        OnClick = chkAutorunElevatedClick
      end
      object chkDiagnostics: TCheckBox
        Left = 12
        Top = 56
        Width = 480
        Height = 17
        Caption = #1042#1077#1089#1090#1080' '#1076#1080#1072#1075#1085#1086#1089#1090#1080#1095#1077#1089#1082#1080#1081' '#1078#1091#1088#1085#1072#1083
        TabOrder = 2
        OnClick = chkDiagnosticsClick
      end
      object chkCheckUpdates: TCheckBox
        Left = 12
        Top = 78
        Width = 480
        Height = 17
        Caption = #1055#1088#1086#1074#1077#1088#1103#1090#1100' '#1085#1072#1083#1080#1095#1080#1077' '#1085#1086#1074#1086#1081' '#1074#1077#1088#1089#1080#1080' '#1088#1072#1079' '#1074' '#1076#1077#1085#1100
        TabOrder = 3
        OnClick = chkBehaviorClick
      end
      object chkPauseFullscreen: TCheckBox
        Left = 12
        Top = 108
        Width = 480
        Height = 17
        Caption = #1053#1077' '#1088#1072#1073#1086#1090#1072#1090#1100' '#1074' '#1087#1086#1083#1085#1086#1101#1082#1088#1072#1085#1085#1099#1093' '#1087#1088#1080#1083#1086#1078#1077#1085#1080#1103#1093' '#1080' '#1080#1075#1088#1072#1093
        TabOrder = 4
        OnClick = chkBehaviorClick
      end
      object chkNotifications: TCheckBox
        Left = 12
        Top = 130
        Width = 480
        Height = 17
        Caption = #1055#1086#1082#1072#1079#1099#1074#1072#1090#1100' '#1091#1074#1077#1076#1086#1084#1083#1077#1085#1080#1077', '#1077#1089#1083#1080' '#1076#1077#1081#1089#1090#1074#1080#1077' '#1085#1077#1074#1086#1079#1084#1086#1078#1085#1086
        TabOrder = 5
        OnClick = chkBehaviorClick
      end
      object chkDisableStickyKeys: TCheckBox
        Left = 12
        Top = 152
        Width = 480
        Height = 17
        Caption = #1054#1090#1082#1083#1102#1095#1080#1090#1100' '#1074#1099#1079#1086#1074' '#1079#1072#1083#1080#1087#1072#1085#1080#1103' '#1082#1083#1072#1074#1080#1096' '#1087#1103#1090#1080#1082#1088#1072#1090#1085#1099#1084' '#1085#1072#1078#1072#1090#1080#1077#1084' Shift'
        TabOrder = 6
        OnClick = chkBehaviorClick
      end
      object chkLayoutIndicator: TCheckBox
        Left = 12
        Top = 174
        Width = 480
        Height = 17
        Caption = #1055#1086#1082#1072#1079#1099#1074#1072#1090#1100' '#1088#1072#1089#1082#1083#1072#1076#1082#1091' '#1088#1103#1076#1086#1084' '#1089' '#1082#1091#1088#1089#1086#1088#1086#1084' '#1087#1088#1080' '#1087#1077#1088#1077#1082#1083#1102#1095#1077#1085#1080#1080
        TabOrder = 7
        OnClick = chkBehaviorClick
      end
      object chkSound: TCheckBox
        Left = 12
        Top = 196
        Width = 480
        Height = 17
        Caption = #1047#1074#1091#1082#1086#1074#1086#1081' '#1089#1080#1075#1085#1072#1083' '#1087#1088#1080' '#1080#1089#1087#1088#1072#1074#1083#1077#1085#1080#1080' '#1090#1077#1082#1089#1090#1072
        TabOrder = 8
        OnClick = chkBehaviorClick
      end
      object lblLanguage: TLabel
        Left = 12
        Top = 229
        Width = 8
        Height = 13
        Caption = #1071#1079#1099#1082' '#1080#1085#1090#1077#1088#1092#1077#1081#1089#1072' / Language:'
      end
      object cbLanguage: TComboBox
        Left = 230
        Top = 226
        Width = 170
        Height = 21
        Style = csDropDownList
        TabOrder = 9
        OnChange = cbLanguageChange
      end
      object lblStorage: TLabel
        Left = 12
        Top = 264
        Width = 8
        Height = 13
        Caption = #1053#1072#1089#1090#1088#1086#1081#1082#1080' '#1093#1088#1072#1085#1103#1090#1089#1103' '#1074' '#1088#1077#1077#1089#1090#1088#1077
      end
      object btnExport: TButton
        Left = 12
        Top = 284
        Width = 160
        Height = 25
        Caption = #1069#1082#1089#1087#1086#1088#1090' '#1085#1072#1089#1090#1088#1086#1077#1082'...'
        TabOrder = 10
        OnClick = btnExportClick
      end
      object btnImport: TButton
        Left = 180
        Top = 284
        Width = 160
        Height = 25
        Caption = #1048#1084#1087#1086#1088#1090' '#1085#1072#1089#1090#1088#1086#1077#1082'...'
        TabOrder = 11
        OnClick = btnImportClick
      end
    end
    object tsHotkeys: TTabSheet
      Caption = #1057#1086#1095#1077#1090#1072#1085#1080#1103
      object lblConvert: TLabel
        Left = 12
        Top = 15
        Width = 8
        Height = 13
        Caption = #1050#1086#1085#1074#1077#1088#1090#1080#1088#1086#1074#1072#1090#1100' '#1088#1072#1089#1082#1083#1072#1076#1082#1091
      end
      object cbConvert: TComboBox
        Left = 240
        Top = 12
        Width = 252
        Height = 21
        Style = csDropDownList
        Tag = 1
        TabOrder = 0
        OnChange = cbGestureChange
      end
      object lblUpper: TLabel
        Left = 12
        Top = 43
        Width = 8
        Height = 13
        Caption = #1055#1088#1077#1086#1073#1088#1072#1079#1086#1074#1072#1090#1100' '#1074' '#1042#1045#1056#1061#1053#1048#1049' '#1088#1077#1075#1080#1089#1090#1088
      end
      object cbUpper: TComboBox
        Left = 240
        Top = 40
        Width = 252
        Height = 21
        Style = csDropDownList
        Tag = 2
        TabOrder = 1
        OnChange = cbGestureChange
      end
      object lblLower: TLabel
        Left = 12
        Top = 71
        Width = 8
        Height = 13
        Caption = #1055#1088#1077#1086#1073#1088#1072#1079#1086#1074#1072#1090#1100' '#1074' '#1085#1080#1078#1085#1080#1081' '#1088#1077#1075#1080#1089#1090#1088
      end
      object cbLower: TComboBox
        Left = 240
        Top = 68
        Width = 252
        Height = 21
        Style = csDropDownList
        Tag = 3
        TabOrder = 2
        OnChange = cbGestureChange
      end
      object lblInvert: TLabel
        Left = 12
        Top = 99
        Width = 8
        Height = 13
        Caption = #1048#1085#1074#1077#1088#1090#1080#1088#1086#1074#1072#1090#1100' '#1088#1077#1075#1080#1089#1090#1088
      end
      object cbInvert: TComboBox
        Left = 240
        Top = 96
        Width = 252
        Height = 21
        Style = csDropDownList
        Tag = 4
        TabOrder = 3
        OnChange = cbGestureChange
      end
      object lblTranslit: TLabel
        Left = 12
        Top = 127
        Width = 8
        Height = 13
        Caption = #1058#1088#1072#1085#1089#1083#1080#1090#1077#1088#1072#1094#1080#1103
      end
      object cbTranslit: TComboBox
        Left = 240
        Top = 124
        Width = 252
        Height = 21
        Style = csDropDownList
        Tag = 5
        TabOrder = 4
        OnChange = cbGestureChange
      end
      object lblUndo: TLabel
        Left = 12
        Top = 155
        Width = 8
        Height = 13
        Caption = #1054#1090#1084#1077#1085#1080#1090#1100' '#1087#1086#1089#1083#1077#1076#1085#1077#1077' '#1080#1089#1087#1088#1072#1074#1083#1077#1085#1080#1077
      end
      object cbUndo: TComboBox
        Left = 240
        Top = 152
        Width = 252
        Height = 21
        Style = csDropDownList
        Tag = 6
        TabOrder = 5
        OnChange = cbGestureChange
      end
      object lblTranslate: TLabel
        Left = 12
        Top = 183
        Width = 8
        Height = 13
        Caption = #1055#1077#1088#1077#1074#1077#1089#1090#1080' '#1074#1099#1076#1077#1083#1077#1085#1085#1086#1077
      end
      object cbTranslate: TComboBox
        Left = 240
        Top = 180
        Width = 252
        Height = 21
        Style = csDropDownList
        Tag = 7
        TabOrder = 6
        OnChange = cbGestureChange
      end
      object lblWebSearch: TLabel
        Left = 12
        Top = 211
        Width = 8
        Height = 13
        Caption = #1053#1072#1081#1090#1080' '#1074#1099#1076#1077#1083#1077#1085#1085#1086#1077' '#1074' '#1080#1085#1090#1077#1088#1085#1077#1090#1077
      end
      object cbWebSearch: TComboBox
        Left = 240
        Top = 208
        Width = 252
        Height = 21
        Style = csDropDownList
        Tag = 8
        TabOrder = 7
        OnChange = cbGestureChange
      end
      object lblTranslateReplace: TLabel
        Left = 12
        Top = 239
        Width = 8
        Height = 13
        Caption = #1053#1072#1081#1090#1080' '#1074#1099#1076#1077#1083#1077#1085#1085#1086#1077' '#1074' '#1080#1085#1090#1077#1088#1085#1077#1090#1077
      end
      object cbTranslateReplace: TComboBox
        Left = 240
        Top = 236
        Width = 252
        Height = 21
        Style = csDropDownList
        Tag = 9
        TabOrder = 8
        OnChange = cbGestureChange
      end
      object lblInterval: TLabel
        Left = 12
        Top = 267
        Width = 8
        Height = 13
        Caption = #1048#1085#1090#1077#1088#1074#1072#1083' '#1076#1074#1086#1081#1085#1086#1075#1086' '#1085#1072#1078#1072#1090#1080#1103':'
      end
      object edInterval: TEdit
        Left = 240
        Top = 264
        Width = 57
        Height = 21
        NumbersOnly = True
        TabOrder = 9
        Text = '500'
        OnChange = edIntervalChange
        OnExit = edIntervalExit
      end
      object udInterval: TUpDown
        Left = 297
        Top = 264
        Width = 16
        Height = 21
        Associate = edInterval
        Min = 200
        Max = 1000
        Increment = 50
        Position = 500
        TabOrder = 10
        Thousands = False
      end
      object lblIntervalUnit: TLabel
        Left = 320
        Top = 267
        Width = 8
        Height = 13
        Caption = #1084#1089
      end
      object lblTranslator: TLabel
        Left = 12
        Top = 299
        Width = 8
        Height = 13
        Caption = #1055#1077#1088#1077#1074#1086#1076#1095#1080#1082':'
      end
      object cbTranslator: TComboBox
        Left = 240
        Top = 296
        Width = 252
        Height = 21
        Style = csDropDownList
        TabOrder = 11
        OnChange = cbServiceChange
      end
      object lblSearchEngine: TLabel
        Left = 12
        Top = 327
        Width = 8
        Height = 13
        Caption = #1055#1086#1080#1089#1082':'
      end
      object cbSearchEngine: TComboBox
        Left = 240
        Top = 324
        Width = 252
        Height = 21
        Style = csDropDownList
        TabOrder = 12
        OnChange = cbServiceChange
      end
      object lblDeepLKey: TLabel
        Left = 12
        Top = 355
        Width = 8
        Height = 13
        Caption = #1050#1083#1102#1095' DeepL API '#1076#1083#1103' '#1079#1072#1084#1077#1085#1099' '#1087#1077#1088#1077#1074#1086#1076#1086#1084':'
      end
      object edDeepLKey: TEdit
        Left = 240
        Top = 352
        Width = 252
        Height = 21
        PasswordChar = '*'
        TabOrder = 13
        OnExit = edCorrectionsExit
      end
    end
    object tsLayout: TTabSheet
      Caption = #1056#1072#1089#1082#1083#1072#1076#1082#1072
      object chkAutoSwitch: TCheckBox
        Left = 12
        Top = 12
        Width = 480
        Height = 17
        Caption = #1040#1074#1090#1086#1084#1072#1090#1080#1095#1077#1089#1082#1080' '#1087#1077#1088#1077#1082#1083#1102#1095#1072#1090#1100' '#1088#1072#1089#1082#1083#1072#1076#1082#1091' '#1076#1083#1103' '#1089#1083#1086#1074', '#1085#1072#1073#1088#1072#1085#1085#1099#1093' '#1085#1077' '#1074' '#1090#1086#1081' '#1088#1072#1089#1082#1083#1072#1076#1082#1077
        TabOrder = 0
        OnClick = chkBehaviorClick
      end
      object lblAutoSwitchHint: TLabel
        Left = 30
        Top = 32
        Width = 8
        Height = 13
        Caption = #1056#1077#1096#1072#1077#1090' '#1087#1088#1086#1074#1077#1088#1082#1072' '#1086#1088#1092#1086#1075#1088#1072#1092#1080#1080' Windows.'
      end
      object chkInWordSwitch: TCheckBox
        Left = 30
        Top = 54
        Width = 470
        Height = 17
        Caption = #1055#1077#1088#1077#1082#1083#1102#1095#1072#1090#1100' '#1091#1078#1077' '#1074#1086' '#1074#1088#1077#1084#1103' '#1085#1072#1073#1086#1088#1072' '#8212' '#1087#1086' '#1085#1077#1074#1086#1079#1084#1086#1078#1085#1086#1084#1091' '#1085#1072#1095#1072#1083#1091' '#1089#1083#1086#1074#1072' (ghb '#8594' '#1087#1088#1080')'
        TabOrder = 1
        OnClick = chkBehaviorClick
      end
      object chkLearnManual: TCheckBox
        Left = 30
        Top = 78
        Width = 470
        Height = 17
        Caption = #1047#1072#1087#1086#1084#1080#1085#1072#1090#1100' '#1089#1083#1086#1074#1072', '#1076#1074#1072#1078#1076#1099' '#1080#1089#1087#1088#1072#1074#1083#1077#1085#1085#1099#1077' '#1074#1088#1091#1095#1085#1091#1102', '#1080' '#1076#1072#1083#1100#1096#1077' '#1087#1077#1088#1077#1082#1083#1102#1095#1072#1090#1100' '#1080#1093' '#1089#1072#1084#1080
        TabOrder = 2
        OnClick = chkBehaviorClick
      end
      object lblAutoSwitchLearned: TLabel
        Left = 30
        Top = 108
        Width = 8
        Height = 13
        Caption = #1042#1089#1077#1075#1076#1072' '#1087#1077#1088#1077#1082#1083#1102#1095#1072#1090#1100' ('#1089#1083#1086#1074#1086' '#1074' '#1089#1090#1088#1086#1082#1077'):'
      end
      object memAutoSwitchLearned: TMemo
        Left = 30
        Top = 126
        Width = 230
        Height = 150
        ScrollBars = ssVertical
        TabOrder = 3
        WordWrap = False
        OnExit = edCorrectionsExit
      end
      object lblAutoSwitchExceptions: TLabel
        Left = 270
        Top = 108
        Width = 8
        Height = 13
        Caption = #1053#1077' '#1080#1089#1087#1088#1072#1074#1083#1103#1090#1100' ('#1089#1083#1086#1074#1086' '#1074' '#1089#1090#1088#1086#1082#1077'):'
      end
      object memAutoSwitchExceptions: TMemo
        Left = 270
        Top = 126
        Width = 230
        Height = 150
        ScrollBars = ssVertical
        TabOrder = 4
        WordWrap = False
        OnExit = edCorrectionsExit
      end
      object lblLayoutNote: TLabel
        Left = 12
        Top = 290
        Width = 8
        Height = 13
        Caption = #1054#1096#1080#1073#1086#1095#1085#1086#1077' '#1087#1077#1088#1077#1082#1083#1102#1095#1077#1085#1080#1077' '#1086#1090#1084#1077#1085#1103#1077#1090#1089#1103' '#1076#1074#1086#1081#1085#1099#1084' Shift '#1080#1083#1080' '#1076#1074#1086#1081#1085#1099#1084' Caps Lock.'
      end
    end
    object tsCorrections: TTabSheet
      Caption = #1048#1089#1087#1088#1072#1074#1083#1077#1085#1080#1103
      object chkFixTypos: TCheckBox
        Left = 12
        Top = 12
        Width = 480
        Height = 17
        Caption = #1048#1089#1087#1088#1072#1074#1083#1103#1090#1100' '#1086#1087#1077#1095#1072#1090#1082#1080': '#1087#1077#1088#1077#1089#1090#1072#1074#1083#1077#1085#1085#1099#1077' '#1089#1086#1089#1077#1076#1085#1080#1077' '#1073#1091#1082#1074#1099' ('#1087#1080#1088#1074#1077#1090' '#8594' '#1087#1088#1080#1074#1077#1090')'
        TabOrder = 0
        OnClick = chkBehaviorClick
      end
      object chkFixTyposExtended: TCheckBox
        Left = 30
        Top = 36
        Width = 470
        Height = 17
        Caption = #1040' '#1090#1072#1082#1078#1077' '#1087#1088#1086#1087#1091#1097#1077#1085#1085#1091#1102', '#1083#1080#1096#1085#1102#1102' '#1080#1083#1080' '#1079#1072#1084#1077#1085#1105#1085#1085#1091#1102' '#1073#1091#1082#1074#1091' ('#1087#1088#1077#1074#1077#1090' '#8594' '#1087#1088#1080#1074#1077#1090')'
        TabOrder = 1
        OnClick = chkBehaviorClick
      end
      object chkCapitalize: TCheckBox
        Left = 12
        Top = 66
        Width = 480
        Height = 17
        Caption = #1047#1072#1075#1083#1072#1074#1085#1072#1103' '#1073#1091#1082#1074#1072' '#1074' '#1085#1072#1095#1072#1083#1077' '#1087#1088#1077#1076#1083#1086#1078#1077#1085#1080#1103' (. '#1087#1088#1080#1074#1077#1090' '#8594' . '#1055#1088#1080#1074#1077#1090')'
        TabOrder = 2
        OnClick = chkBehaviorClick
      end
      object chkDoubleSpace: TCheckBox
        Left = 12
        Top = 90
        Width = 480
        Height = 17
        Caption = #1059#1073#1080#1088#1072#1090#1100' '#1089#1083#1091#1095#1072#1081#1085#1099#1081' '#1076#1074#1086#1081#1085#1086#1081' '#1087#1088#1086#1073#1077#1083
        TabOrder = 3
        OnClick = chkBehaviorClick
      end
      object chkFixCapsLock: TCheckBox
        Left = 12
        Top = 114
        Width = 480
        Height = 17
        Caption = #1048#1089#1087#1088#1072#1074#1083#1103#1090#1100' '#1089#1083#1086#1074#1072', '#1085#1072#1073#1088#1072#1085#1085#1099#1077' '#1089' '#1074#1082#1083#1102#1095#1105#1085#1085#1099#1084' Caps Lock ('#1087#1056#1048#1042#1045#1058' '#8594' '#1055#1088#1080#1074#1077#1090')'
        TabOrder = 4
        OnClick = chkBehaviorClick
      end
      object chkFixTwoCapitals: TCheckBox
        Left = 12
        Top = 138
        Width = 480
        Height = 17
        Caption = #1048#1089#1087#1088#1072#1074#1083#1103#1090#1100' '#1076#1074#1077' '#1079#1072#1075#1083#1072#1074#1085#1099#1077' '#1073#1091#1082#1074#1099' '#1074' '#1085#1072#1095#1072#1083#1077' '#1089#1083#1086#1074#1072' ('#1055#1056#1080#1074#1077#1090' '#8594' '#1055#1088#1080#1074#1077#1090')'
        TabOrder = 5
        OnClick = chkBehaviorClick
      end
      object lblTwoCapsExceptions: TLabel
        Left = 30
        Top = 164
        Width = 8
        Height = 13
        Caption = #1048#1089#1082#1083#1102#1095#1077#1085#1080#1103' '#1076#1083#1103' '#1076#1074#1091#1093' '#1079#1072#1075#1083#1072#1074#1085#1099#1093' ('#1089#1083#1086#1074#1086' '#1074' '#1089#1090#1088#1086#1082#1077'):'
      end
      object memTwoCapsExceptions: TMemo
        Left = 30
        Top = 182
        Width = 470
        Height = 100
        ScrollBars = ssVertical
        TabOrder = 6
        WordWrap = False
        OnExit = edCorrectionsExit
      end
      object lblCorrectionsNote: TLabel
        Left = 12
        Top = 296
        Width = 8
        Height = 13
        Caption = #1048#1089#1087#1088#1072#1074#1083#1077#1085#1080#1103' '#1074#1099#1087#1086#1083#1085#1103#1102#1090#1089#1103' '#1087#1086#1089#1083#1077' '#1087#1088#1086#1073#1077#1083#1072'. '#1054#1090#1084#1077#1085#1080#1090#1100' '#1087#1086#1089#1083#1077#1076#1085#1077#1077' '#8212' '#1076#1074#1086#1081#1085#1086#1081' Caps Lock.'
      end
    end
    object tsSnippets: TTabSheet
      Caption = #1047#1072#1084#1077#1085#1099
      object chkSnippets: TCheckBox
        Left = 12
        Top = 12
        Width = 480
        Height = 17
        Caption = #1047#1072#1084#1077#1085#1103#1090#1100' '#1096#1072#1073#1083#1086#1085#1099': '#1089#1086#1082#1088#1072#1097#1077#1085#1080#1077' '#1080' '#1087#1088#1086#1073#1077#1083
        TabOrder = 0
        OnClick = chkBehaviorClick
      end
      object lblSnippetsHint: TLabel
        Left = 30
        Top = 34
        Width = 8
        Height = 13
        Caption = #1050#1072#1078#1076#1072#1103' '#1089#1090#1088#1086#1082#1072': '#1089#1086#1082#1088#1072#1097#1077#1085#1080#1077'='#1090#1077#1082#1089#1090'.'
      end
      object memSnippets: TMemo
        Left = 30
        Top = 84
        Width = 470
        Height = 112
        ScrollBars = ssVertical
        TabOrder = 1
        WordWrap = False
        OnExit = edCorrectionsExit
      end
      object chkAutoReplace: TCheckBox
        Left = 12
        Top = 206
        Width = 490
        Height = 17
        Caption = #1040#1074#1090#1086#1094#1077#1085#1079#1091#1088#1072': '#1079#1072#1084#1077#1085#1103#1090#1100' '#1089#1083#1086#1074#1072' '#1087#1086' '#1089#1087#1088#1072#1074#1086#1095#1085#1080#1082#1091
        TabOrder = 2
        OnClick = chkBehaviorClick
      end
      object lblAutoReplaceHint: TLabel
        Left = 30
        Top = 226
        Width = 8
        Height = 13
        Caption = #1050#1072#1078#1076#1072#1103' '#1089#1090#1088#1086#1082#1072': '#1089#1083#1086#1074#1086'='#1079#1072#1084#1077#1085#1072'.'
      end
      object memAutoReplace: TMemo
        Left = 30
        Top = 256
        Width = 470
        Height = 108
        ScrollBars = ssVertical
        TabOrder = 3
        WordWrap = False
        OnExit = edCorrectionsExit
      end
    end
    object tsExclusions: TTabSheet
      Caption = #1048#1089#1082#1083#1102#1095#1077#1085#1080#1103
      object lblPrograms: TLabel
        Left = 12
        Top = 10
        Width = 8
        Height = 13
        Caption = #1055#1088#1086#1075#1088#1072#1084#1084#1099
      end
      object edProgramFilter: TEdit
        Left = 12
        Top = 44
        Width = 200
        Height = 21
        TabOrder = 0
        OnChange = edProgramFilterChange
      end
      object chkProgramsCheckedOnly: TCheckBox
        Left = 226
        Top = 46
        Width = 200
        Height = 17
        Caption = #1058#1086#1083#1100#1082#1086' '#1086#1090#1084#1077#1095#1077#1085#1085#1099#1077
        TabOrder = 1
        OnClick = chkProgramsCheckedOnlyClick
      end
      object sgPrograms: TStringGrid
        Left = 12
        Top = 72
        Width = 492
        Height = 262
        ColCount = 4
        DefaultRowHeight = 20
        FixedCols = 0
        RowCount = 2
        Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goColSizing, goThumbTracking]
        TabOrder = 2
        OnDrawCell = sgProgramsDrawCell
        OnKeyDown = sgProgramsKeyDown
        OnMouseUp = sgProgramsMouseUp
        OnSelectCell = sgProgramsSelectCell
      end
      object btnAddProgram: TButton
        Left = 12
        Top = 342
        Width = 150
        Height = 25
        Caption = #1044#1086#1073#1072#1074#1080#1090#1100' '#1087#1088#1086#1075#1088#1072#1084#1084#1091'...'
        TabOrder = 3
        OnClick = btnAddProgramClick
      end
      object btnRemoveProgram: TButton
        Left = 170
        Top = 342
        Width = 130
        Height = 25
        Caption = #1059#1073#1088#1072#1090#1100' '#1080#1079' '#1089#1087#1080#1089#1082#1072
        Enabled = False
        TabOrder = 4
        OnClick = btnRemoveProgramClick
      end
      object btnDefaultPrograms: TButton
        Left = 384
        Top = 342
        Width = 120
        Height = 25
        Caption = #1055#1086' '#1091#1084#1086#1083#1095#1072#1085#1080#1102
        TabOrder = 5
        OnClick = btnDefaultProgramsClick
      end
    end
  end
  object btnReport: TButton
    Left = 304
    Top = 420
    Width = 136
    Height = 25
    Caption = #1057#1086#1073#1088#1072#1090#1100' '#1086#1090#1095#1105#1090'...'
    TabOrder = 1
    OnClick = mniReportClick
  end
  object btnClose: TButton
    Left = 452
    Top = 420
    Width = 80
    Height = 25
    Cancel = True
    Caption = #1047#1072#1082#1088#1099#1090#1100
    TabOrder = 2
    OnClick = btnCloseClick
  end
  object TrayIcon: TTrayIcon
    Hint = 'LayoutSwitcher'
    BalloonTitle = 'LayoutSwitcher'
    PopupMenu = PopupMenu
    Visible = True
    OnBalloonClick = TrayIconBalloonClick
    OnDblClick = TrayIconDblClick
    Left = 416
    Top = 8
  end
  object PopupMenu: TPopupMenu
    Left = 416
    Top = 64
    object mniSettings: TMenuItem
      Default = True
      OnClick = mniSettingsClick
      Caption = #1053#1072#1089#1090#1088#1086#1081#1082#1080'...'
    end
    object mniSeparator1: TMenuItem
      Caption = '-'
    end
    object mniClipboard: TMenuItem
      Caption = #1058#1077#1082#1089#1090' '#1074' '#1073#1091#1092#1077#1088#1077' '#1086#1073#1084#1077#1085#1072
      object mniClipConvert: TMenuItem
        Tag = 1
        OnClick = mniClipboardClick
        Caption = #1048#1089#1087#1088#1072#1074#1080#1090#1100' '#1088#1072#1089#1082#1083#1072#1076#1082#1091
      end
      object mniClipUpper: TMenuItem
        Tag = 2
        OnClick = mniClipboardClick
        Caption = #1042#1045#1056#1061#1053#1048#1049' '#1088#1077#1075#1080#1089#1090#1088
      end
      object mniClipLower: TMenuItem
        Tag = 3
        OnClick = mniClipboardClick
        Caption = #1085#1080#1078#1085#1080#1081' '#1088#1077#1075#1080#1089#1090#1088
      end
      object mniClipTranslit: TMenuItem
        Tag = 5
        OnClick = mniClipboardClick
        Caption = #1058#1088#1072#1085#1089#1083#1080#1090#1077#1088#1072#1094#1080#1103
      end
    end
    object mniSeparator3: TMenuItem
      Caption = '-'
    end
    object mniPause15: TMenuItem
      Tag = 15
      OnClick = mniPauseClick
      Caption = #1055#1088#1080#1086#1089#1090#1072#1085#1086#1074#1080#1090#1100' '#1085#1072' 15 '#1084#1080#1085#1091#1090
    end
    object mniPause60: TMenuItem
      Tag = 60
      OnClick = mniPauseClick
      Caption = #1055#1088#1080#1086#1089#1090#1072#1085#1086#1074#1080#1090#1100' '#1085#1072' 1 '#1095#1072#1089
    end
    object mniPauseIndefinite: TMenuItem
      Tag = -1
      OnClick = mniPauseClick
      Caption = #1055#1088#1080#1086#1089#1090#1072#1085#1086#1074#1080#1090#1100' '#1076#1086' '#1074#1086#1079#1086#1073#1085#1086#1074#1083#1077#1085#1080#1103
    end
    object mniResume: TMenuItem
      Visible = False
      OnClick = mniResumeClick
      Caption = #1042#1086#1079#1086#1073#1085#1086#1074#1080#1090#1100' '#1088#1072#1073#1086#1090#1091
    end
    object mniSeparator2: TMenuItem
      Caption = '-'
    end
    object mniDownloadUpdate: TMenuItem
      Visible = False
      OnClick = mniDownloadUpdateClick
      Caption = #1057#1082#1072#1095#1072#1090#1100' '#1085#1086#1074#1091#1102' '#1074#1077#1088#1089#1080#1102
    end
    object mniCheckUpdates: TMenuItem
      OnClick = mniCheckUpdatesClick
      Caption = #1055#1088#1086#1074#1077#1088#1080#1090#1100' '#1086#1073#1085#1086#1074#1083#1077#1085#1080#1103
    end
    object mniReport: TMenuItem
      OnClick = mniReportClick
      Caption = #1057#1086#1073#1088#1072#1090#1100' '#1086#1090#1095#1105#1090'...'
    end
    object mniDiagnostics: TMenuItem
      OnClick = mniDiagnosticsClick
      Caption = #1054#1090#1082#1088#1099#1090#1100' '#1087#1072#1087#1082#1091' '#1076#1080#1072#1075#1085#1086#1089#1090#1080#1082#1080
    end
    object mniSeparator: TMenuItem
      Caption = '-'
    end
    object mniExit: TMenuItem
      OnClick = mniExitClick
      Caption = #1042#1099#1093#1086#1076
    end
  end
  object TimerLayout: TTimer
    Interval = 250
    OnTimer = TimerLayoutTimer
    Left = 352
    Top = 8
  end
  object TimerPause: TTimer
    Enabled = False
    OnTimer = TimerPauseTimer
    Left = 296
    Top = 8
  end
  object TimerUpdate: TTimer
    Enabled = False
    Interval = 60000
    OnTimer = TimerUpdateTimer
    Left = 240
    Top = 8
  end
end
