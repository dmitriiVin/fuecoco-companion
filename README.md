<h1 align="center">Фуэкоко</h1>

<p align="center">
  <img src="docs/fuecoco-moves.gif" width="224" height="150" alt="Фуэкоко машет лапой, подпрыгивает, оглядывается, бегает, чихает, пускает сердечки и засыпает">
</p>

<p align="center">
  Пиксельный питомец для рабочего стола. Пока собирается проект, Фуэкоко горит.<br>
  Когда работа стихает, он машет лапой, дремлет или отправляется на короткую пробежку.
</p>

<p align="center">
  <strong>Собрать для</strong>&ensp;
  <a href="#macos">macOS</a> ·
  <a href="#arch-linux">Arch Linux</a> ·
  <a href="#ubuntu">Ubuntu</a> ·
  <a href="#debian">Debian</a>
</p>

## Что умеет Фуэкоко

Питомец сидит в выбранном углу поверх окон и пропускает щелчки мыши. В меню можно сменить угол. Откройте **«Анимации»**, чтобы Фуэкоко помахал лапой, пробежался туда и обратно, чихнул или пустил сердечки.

| Когда | Что делает Фуэкоко |
| --- | --- |
| На компьютере собирается проект | Загорается, в том числе при сборке из IDE или терминала. |
| Команда через `fuecoco-build` вернула ошибку | Плачет около девяти секунд. |
| Выдалась свободная минута | Может уснуть, подпрыгнуть, оглядеться, помахать, чихнуть с облачком или пустить три розовых сердечка. Между жестами проходит 55–115 секунд отдыха. |
| Накопилось 5–15 минут простоя | Пробегает 44 точки к центру экрана и возвращается в свой угол. |

**На Mac** он также показывает видимые уведомления текстом над головой, рычит после завершения загрузки и реагирует на работу и ошибки Codex. Через меню можно прочитать выделенный текст вслух, распознать текст на картинке, изменить размер изображения или собрать PDF.

В меню «Анимации» видно, сколько минут простоя осталось до автоматической пробежки. Сборки и активная задача Codex ставят отсчёт на паузу. Командой **«Пробежаться»** можно запустить короткую пробежку даже во время работы. После возвращения Фуэкоко снова показывает текущее состояние. При включённом уменьшении движения пробежки отключены.

## Сборка из исходников

Каждый блок ниже рассчитан на новую копию репозитория. Во время первой сборки скрипт скачивает спрайт-лист и проверяет его SHA-256.

### macOS

Нужны macOS 13 или новее, Python 3.9+ и инструменты командной строки Xcode. При первой установке выполните `xcode-select --install` и дождитесь завершения. [Инструкция Apple](https://developer.apple.com/documentation/xcode/installing-the-command-line-tools/)

```sh
git clone https://github.com/dmitriiVin/fuecoco-companion.git
cd fuecoco-companion
python3 -m venv .venv
. .venv/bin/activate
python3 -m pip install 'Pillow>=9.1'
./scripts/build-mac.sh
open build/Fuecoco.app
```

Готовое приложение лежит в **`build/Fuecoco.app`**. Для постоянной установки закройте питомца и перетащите приложение в «Программы». Меню открывается по значку пламени в строке меню macOS. Пробежки отключает системная настройка «Уменьшение движения».

Для чтения выделенного текста и показа баннеров может понадобиться разрешение «Универсальный доступ», для загрузок — доступ к папке «Загрузки».

### Arch Linux

```sh
sudo pacman -Syu --needed git gcc make python-pyqt6 python-pillow ca-certificates
git clone https://github.com/dmitriiVin/fuecoco-companion.git
cd fuecoco-companion
./scripts/install-linux.sh
~/.local/bin/fuecoco
```

Установщик компилирует общее ядро на C и добавляет Фуэкоко в меню приложений текущего пользователя. [Пакет PyQt6 в Arch](https://archlinux.org/packages/extra/x86_64/python-pyqt6/)

### Ubuntu

Команды для **Ubuntu 24.04 LTS**. Пакет `python3-pyqt6` доступен в репозитории Universe. [Пакет PyQt6 в Ubuntu](https://packages.ubuntu.com/noble/python3-pyqt6)

```sh
sudo apt update
sudo apt install git gcc libc6-dev make python3-pyqt6 python3-pil ca-certificates
git clone https://github.com/dmitriiVin/fuecoco-companion.git
cd fuecoco-companion
./scripts/install-linux.sh
~/.local/bin/fuecoco
```

### Debian

Команды для **Debian 13 (Trixie)**. [Пакет PyQt6 в Debian](https://packages.debian.org/trixie/python3-pyqt6)

```sh
sudo apt update
sudo apt install git gcc libc6-dev make python3-pyqt6 python3-pil ca-certificates
git clone https://github.com/dmitriiVin/fuecoco-companion.git
cd fuecoco-companion
./scripts/install-linux.sh
~/.local/bin/fuecoco
```

<details>
<summary><strong>Окно, трей и обновления в Linux</strong></summary>

Для запуска нужна графическая сессия. На X11 Фуэкоко запрашивает размещение поверх окон. На Wayland позицию и порядок окон определяет композитор. Если доступен XWayland, попробуйте `QT_QPA_PLATFORM=xcb ~/.local/bin/fuecoco`. Меню в трее доступно на панелях с поддержкой системных значков.

При запуске можно выбрать угол и ограничить движение, например `~/.local/bin/fuecoco --corner top-right --reduce-motion`.

Чтобы обновиться, закройте питомца, выполните `git pull --ff-only` в каталоге репозитория и снова запустите `./scripts/install-linux.sh`. Для удаления закройте питомца и удалите каталог `${XDG_DATA_HOME:-$HOME/.local/share}/fuecoco-companion`, ярлык `${XDG_DATA_HOME:-$HOME/.local/share}/applications/fuecoco.desktop` и команды `~/.local/bin/fuecoco` и `~/.local/bin/fuecoco-build`.

</details>

## Как подключить свою сборку

Раз в две секунды Фуэкоко проверяет процессы текущего пользователя. Он узнаёт, например, Make, Ninja, CMake, Xcode, Cargo, Go, .NET, Gradle, Maven, Flutter, Zig, Webpack и `npm run build`. Очень короткая сборка может закончиться между проверками.

Чтобы Фуэкоко заметил короткую или нестандартную команду и узнал её результат, запустите её через `fuecoco-build`. Ниже приведены команды для сборки Rust-проекта из его каталога.

```sh
# macOS, если Фуэкоко установлен в «Программы»
/Applications/Fuecoco.app/Contents/Resources/fuecoco-build cargo build --release

# Linux
~/.local/bin/fuecoco-build cargo build --release
```

Обёртка возвращает код выхода команды. При успехе огонь виден ещё около трёх секунд, при ошибке появляются слёзы. Для удалённой сборки оберните локальную команду, которая ждёт результата.

## Как устроен проект

| Каталог | Содержимое |
| --- | --- |
| [macos/](macos/) | Окно на Swift и AppKit, меню, уведомления, загрузки и действия с файлами. |
| [linux/](linux/) | Прозрачное окно и меню на Python и PyQt6. |
| [shared/](shared/) | Общее ядро на C. Выбирает кадры и движения, распознаёт процессы сборки. |
| [scripts/](scripts/) | Сборка для Mac, установка в Linux, подготовка графики и синтез рычания. |
| [tests/](tests/) | Проверки анимаций, распознавания реальной сборки Make и отрисовки Linux-окна. |

Из корня репозитория запустите `./tests/smoke.sh`, когда остальные сборки завершены. Для проверки отрисовки в Linux после установки выполните `QT_QPA_PLATFORM=offscreen /usr/bin/python3 tests/linux_ui.py`. [Результаты проверок Arch, Ubuntu и Debian](https://github.com/dmitriiVin/fuecoco-companion/actions/workflows/linux.yml)

<details>
<summary><strong>Графика, автономная сборка и пакет для Codex</strong></summary>

Оригинальные кадры взяты из каталога Pets Codex. Персонаж Fuecoco и исходная графика принадлежат соответствующим правообладателям. [Страница Фуэкоко в каталоге](https://petscodex.com/pets/fuecoco)

Если оригинальный спрайт-лист уже скачан, передайте `--sheet /путь/к/spritesheet.webp` скрипту `build-mac.sh` или `install-linux.sh`. Контрольная сумма проверяется и для локального файла.

Чтобы собрать отдельный пакет для Codex, запустите `python3 scripts/assets.py build/frames --codex build/codex/fuecoco` в окружении с Pillow. В `build/codex/fuecoco/` появятся `pet.json` и `spritesheet.webp`.

</details>
