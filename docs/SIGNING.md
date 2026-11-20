# Подпись релизов через SignPath

[SignPath Foundation](https://signpath.org) бесплатно подписывает открытые проекты своим сертификатом. Издателем в свойствах файла и в окне SmartScreen будет «SignPath Foundation». Подпись выполняет сервис SignPath.io: он принимает файлы только из сборки GitHub Actions этого репозитория, и каждый запрос на подпись вы утверждаете вручную.

Всё, что нужно в репозитории, уже есть:

* лицензия MIT — `LICENSE`, сторонние материалы — `THIRD-PARTY-NOTICES.md`;
* разделы **Code signing policy** и **Privacy policy** в `README.md`;
* workflow `.github/workflows/release.yml`;
* конфигурации артефактов — `.signpath/artifact-configurations/`.

Ниже — шаги, которые можете сделать только вы.

## 1. Подготовить GitHub

1. Включите двухфакторную аутентификацию в GitHub (Settings → Password and authentication). SignPath требует её от всех участников.
2. Отправьте ветку с этими изменениями и слейте её в `master`: заявку рассматривают по содержимому репозитория (лицензия, политика подписи).
3. Желательно защитить `master` правилом (Settings → Rules → Rulesets): запрет force push и изменения только через pull request. SignPath может проверять такие правила при подписи.

## 2. Подать заявку в SignPath Foundation

1. Откройте https://signpath.org/apply и заполните форму:
   * Repository: `https://github.com/Len-A-R/LayoutSwitcher`;
   * License: MIT;
   * Download page: страница релизов `https://github.com/Len-A-R/LayoutSwitcher/releases`;
   * Build system: GitHub Actions (self-hosted runner, см. ниже);
   * описание: что делает программа (можно взять первые абзацы README).
2. Дождитесь ответа по почте. Обычно это занимает от нескольких дней до пары недель. Фонд проверяет, что проект открытый, поддерживается и уже выпускался.

**О сборке.** Delphi нельзя поставить на раннеры, которые предоставляет GitHub, поэтому workflow работает на собственном раннере (ваш компьютер с RAD Studio). SignPath это поддерживает, но фонд вправе требовать сборку на раннерах GitHub. Укажите в заявке, что проект на Delphi собирается на self-hosted runner, и спросите, подходит ли это. Если не подходит, остаётся вариант с собственным сертификатом (подпись через `build-release.cmd`, см. README).

## 3. Настроить проект в SignPath (после одобрения)

Фонд создаст организацию в https://app.signpath.io и пригласит вас. В ней:

1. **Projects → Add project**: slug `LayoutSwitcher`, репозиторий GitHub.
2. **Artifact configurations** (в проекте) — две конфигурации; содержимое скопируйте из файлов репозитория:
   * slug `executables` — `.signpath/artifact-configurations/executables.xml`;
   * slug `installer` — `.signpath/artifact-configurations/installer.xml`.
3. **Signing policies**: политика со slug `release-signing` и сертификатом SignPath Foundation; в Approvers укажите себя. Для неё включите **Trusted Build System → GitHub.com**.
4. Установите **SignPath GitHub App** для репозитория (ссылку даст SignPath). По ней сервис проверяет, что файлы собраны workflow этого репозитория.
5. **Users → ваш пользователь → API token**, либо отдельный CI-пользователь с ролью Submitter в политике. Скопируйте токен.
6. Запомните **Organization ID** (Settings организации).

## 4. Секреты в GitHub

Settings репозитория → Secrets and variables → Actions:

* **Secrets → New repository secret**: `SIGNPATH_API_TOKEN` — токен из шага 3.5;
* **Variables → New repository variable**: `SIGNPATH_ORGANIZATION_ID` — ID организации.

## 5. Собственный раннер

На компьютере, где установлены RAD Studio 12 (путь `C:\Program Files (x86)\Embarcadero\Studio\23.0`) и Inno Setup 7:

1. Settings репозитория → Actions → Runners → **New self-hosted runner** → Windows x64. Выполните показанные команды в PowerShell (папка, например, `C:\actions-runner`).
2. При настройке (`config.cmd`) добавьте метки: `delphi` (метки `self-hosted` и `windows` добавляются сами).
3. Запускайте раннер под своей учётной записью (`run.cmd`) или как службу. Если раннер работает как служба, у её учётной записи должна быть лицензия RAD Studio. Проще всего запускать службу от вашего пользователя.

Сборка в GitHub Actions выполняет только `build-release.cmd /binaries` и `/package`: модульные тесты запускаются, интеграционные — нет (им нужен рабочий стол). Интеграционные тесты запускайте перед выпуском локально: `powershell -File tools\run-integration.ps1`.

## 6. Выпуск подписанного релиза

1. Поднимите версию (Version Info, «All configurations»), закоммитьте и отправьте.
2. Создайте и отправьте тег: `git tag v2.4.0` и `git push origin v2.4.0`.
3. Workflow соберёт программу и отправит `LS.exe` на подпись. На сайте SignPath (или по письму) **утвердите** запрос — сборка ждёт до часа.
4. Затем он соберёт установщик, отправит его на подпись (второе утверждение) и создаст **черновик релиза** со всеми файлами и `winget-manifests-<версия>.zip`.
5. Проверьте черновик, добавьте описание изменений и опубликуйте его.
6. Манифесты winget из архива отправьте как раньше (`wingetcreate submit <папка>` или пулл-реквестом в `microsoft/winget-pkgs`). SHA-256 в них уже от подписанного установщика.

## Что изменится для пользователей

* В свойствах `LS.exe` и установщика появится вкладка «Цифровые подписи» с издателем SignPath Foundation, а SmartScreen со временем перестанет предупреждать (репутация копится по сертификату).
* Встроенное обновление: подписанная программа принимает только установщик с действительной подписью того же издателя (`uSignature.pas`). Переход с неподписанной версии на подписанную проходит как обычно.
