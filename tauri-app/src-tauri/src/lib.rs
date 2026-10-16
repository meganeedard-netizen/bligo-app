#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
  tauri::Builder::default()
    .plugin(tauri_plugin_opener::init())
    .setup(|app| {
      if cfg!(debug_assertions) {
        app.handle().plugin(
          tauri_plugin_log::Builder::default()
            .level(log::LevelFilter::Info)
            .build(),
        )?;
      }
      // Windows (16/10/2026) : WebView2 refusait la caméra (« Permission
      // denied ») pour le scan des cartes et des codes-barres. On autorise la
      // caméra du logiciel, comme le fait déjà WKWebView sur Mac.
      #[cfg(windows)]
      {
        use tauri::Manager;
        if let Some(window) = app.get_webview_window("main") {
          let _ = window.with_webview(|webview| unsafe {
            use webview2_com::Microsoft::Web::WebView2::Win32::*;
            use webview2_com::PermissionRequestedEventHandler;
            if let Ok(core) = webview.controller().CoreWebView2() {
              let mut token = 0i64;
              let _ = core.add_PermissionRequested(
                &PermissionRequestedEventHandler::create(Box::new(|_, args| {
                  let Some(args) = args else { return Ok(()) };
                  let mut kind = COREWEBVIEW2_PERMISSION_KIND::default();
                  args.PermissionKind(&mut kind)?;
                  if kind == COREWEBVIEW2_PERMISSION_KIND_CAMERA {
                    args.SetState(COREWEBVIEW2_PERMISSION_STATE_ALLOW)?;
                  }
                  Ok(())
                })),
                &mut token,
              );
            }
          });
        }
      }
      Ok(())
    })
    .run(tauri::generate_context!())
    .expect("error while running tauri application");
}
