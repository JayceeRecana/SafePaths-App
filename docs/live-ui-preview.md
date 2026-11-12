**SafePaths live UI preview**

Open this project folder in VS Code. Install the Flutter extension by Dart Code if it is missing; it includes the Dart extension. Keep the existing Pixel_9 emulator running, select it in VS Code's device selector, open Run and Debug, select **SafePaths Test - Live UI**, and press F5. The first debug build/install takes longer; leave the emulator visible beside the editor.

This launch configuration uses lib/main.dart, the fieldtest flavor and the same public test configuration as the inspected test APK. It runs in debug mode so hot reload is available. Flutter run uses the version in pubspec.yaml; this Flutter version does not accept --build-name or --build-number on run. A separately built APK may have a higher version code, so switching from that APK to this preview may require uninstalling SafePaths Test first, which removes local app data and saved login. The preview uses the existing test app/package and test backend. No server credential belongs in the launch arguments.

Sign in using the preset test account for the role being adjusted, open the target screen, then request small changes to labels, spacing, colors or layout. Reload after each coherent edit to see the result. In a VS Code debug session use the lightning-bolt Hot Reload action (or Ctrl+F5). Hot reload on save is enabled for Dart edits; changes made by external tools might still require that explicit reload action. This setup does not enable global editor autosave.

An agent-controlled alternative is to start a persistent `flutter run` terminal session with the same arguments and send `r` after each edit. That lets the agent trigger reloads while the user watches the emulator. Use one launch session at a time. `R` performs a hot restart, which resets in-memory state; native/plugin changes require a full stop/start. On October 26, 2026, the first debug build installed and launched successfully on emulator-5554 after the user uninstalled the older test APK. A no-change hot reload completed successfully in 648 ms. Resident sign-in and visual review are the next manual steps.

The UI updates after a reload rather than displaying each individual typing keystroke. Most Dart layout changes can preserve the current app state, but initializers/main/initState changes can require restart. Debug mode is for visual iteration; performance and notification/background acceptance still need appropriate device/release checks. Keep using TEST AREA and the preset test cohort.

The repository's private test configuration files are not included in these editor files. The public configurations now live in `config/build/fieldtest.json` and `config/build/marulas.json`. The VS Code launch choices select the matching flavor and settings; original baseline paths are retained for older commands.

References: [Flutter hot reload](https://docs.flutter.dev/tools/hot-reload), [VS Code setup](https://docs.flutter.dev/tools/vs-code), [Dart Code launch configuration](https://dartcode.org/docs/launch-configuration/).


Workspace organization was refreshed on November 4, 2026. Use `SafePaths Test - Live UI` for the nearby test area, or `SafePaths Marulas - Live UI` for the main candidate. The current installable APKs are linked from [releases](../releases/README.md). Generated build caches were removed, so the next debug build may take longer; no installed app was removed.
