# Floats

Round buttons that float above every window on Windows, one per app. Click a button to bring its app to the front, or open it if it isn't running. Click it again to minimise the app.

Floats is a single [AutoHotkey v2](https://www.autohotkey.com) script, `Floats.ahk`. There is nothing to build or install.

## Features

- **Buttons for anything.** A button can open an installed app, a program, a shortcut, a file, a folder, a website, or a window that is already open.
- **One hub for all of them.** The buttons hide behind a single Floats button. When you point at it, they fan out in a circle around it and slide back in when you move away.
- **The app you're using stays out.** Its button sits straight above or below the hub, so one click minimises it.
- **Drag and drop.** Drop a file, folder or shortcut on any button to add it. Drag a button to the bin to remove it, or onto another button in the fan to swap their places.
- **Your look, per button.** Each button has its own icon, colour and size. Square logos are cropped into a circle automatically, or you can choose to crop or not for each button.
- **Names that keep up.** A button named after its app or web app picks up the new name when the app is renamed, within about 10 minutes. A name you typed yourself stays.
- **Shortcut keys.** Give a button a key combination, such as Ctrl+Alt+D, that works like clicking it.
- **Above full-screen windows.** Floats runs with UI Access, so a full-screen viewer can't cover the buttons. Shortcut keys still work when an administrator program is in front.
- **Starts with Windows.** You can switch this off in the manager.

## Getting started

1. Install [AutoHotkey v2](https://www.autohotkey.com). Keep the standard install folder, `C:\Program Files\AutoHotkey`. UI Access only works from there.
2. Double-click `Floats.ahk`. The manager opens.
3. Click **Add…**, then pick what the button opens. **Apps…** lists your installed apps, or use **File…**, **Folder…** or a web address. Then click **Save**. Once you have a button, you can also just drop files and shortcuts on it.

On first run Floats also:

- sets itself to start with Windows
- adds **Floats** to the Start menu

To open the manager again, use any of these:

- run `Floats.ahk` again
- choose **Floats** in the Start menu
- click the tray icon
- right-click any button

## Using the buttons

| Do this | What happens |
| --- | --- |
| Click a button | Its app comes to the front, or opens if it isn't running |
| Click it again while the app is in front | The app is minimised |
| Point at the hub | The grouped buttons fan out around it |
| Drop a file, folder or shortcut on any button | It's added as a new button, with an Undo message |
| Drag a separate button or the hub | It moves, and remembers the spot |
| Drag a fan button onto another fan button | The two swap places |
| Drag a fan button anywhere else | It slides back to its spot |
| Drag a button to the bin | It's removed from Floats, with an Undo message |
| Hover over a button | Its name and shortcut key are shown |
| Right-click a button | A menu to edit, hide, remove, add or manage buttons, and to exit |

### Adding and removing by dragging

Dropping only points Floats at your file; nothing is moved. A dropped shortcut is copied into Floats' own folder, so the button keeps working if you delete the shortcut from your desktop. A file or folder that later moves or is deleted leaves its button broken. If you drop something that's already in Floats, it isn't added twice.

Only real files, folders and shortcuts can be dropped. For websites and apps from the Start menu, use **Add…**.

The bin appears at the bottom centre of the screen only while a button is being dragged. It removes the button, never the app or file itself. The hub can't be removed: it goes away by itself when fewer than two buttons are left in the group.

### How the buttons fan out

The buttons open in a circle around the hub, facing away from the edges of the screen:

- **At the side of the screen** (the usual place): half a circle.
- **In a corner**: a quarter circle.
- **Out in the open**: a full circle. Up to three buttons fan out toward the middle of the screen. Four or more spread evenly all round, starting at the top and going clockwise.

Each button always pops out in the same spot. The top of the manager list is nearest the hub, so your favourites stay where your hand expects them.

While the fan is closed, the button of the app in front sits straight above the hub, or below it when the hub is in the top half of the screen. When the fan opens it glides to its own spot with the others, and back again when the fan closes.

**With many buttons**, Floats adds more rings. When a ring is full, the next buttons go into a bigger ring around it, like a honeycomb. Next to the side of the screen, the first ring holds 4 or 5 buttons, the second about 7 and the third about 10. That's over 20 buttons in three rings. If one slightly wider ring can hold all the remaining buttons, Floats uses that instead of starting a new ring.

To keep a button always visible outside the group, edit it and tick **Keep on its own**. To show every button separately, untick **Group the buttons behind one Floats button** in the manager.

### Button shape

Under **Shape** in a button's settings:

- **Automatic** (the default): square logos are cropped round, and logos with their own shape are left as they are.
- **Always crop the logo round**: the logo fills the whole circle.
- **Keep the logo's own shape**: the logo sits inside the coloured circle.

## Files

| Where | What |
| --- | --- |
| `Floats.ahk` | The whole app |
| `%AppData%\Floats\floats.ini` | Your buttons and their positions. Saved as UTF-16; easiest to change in the manager |
| `%AppData%\Floats\icons\` | Copies of pictures you chose for buttons |
| `%AppData%\Floats\shortcuts\` | Copies of shortcuts you dropped on a button |
| `%AppData%\Floats\floats.ico` | Floats' own icon |
| `Startup\Floats.lnk` | Starts Floats with Windows, using `--startup` |
| `Start Menu\Programs\Floats.lnk` | Opens the manager |

### Command-line options

- `--startup`: start without opening the manager. The Startup shortcut uses this.
- `--data=<folder>`: use a different settings folder, for example to try changes without touching your own buttons.

## Uninstalling

1. Right-click a button and choose **Exit Floats**.
2. Delete `Floats.lnk` from your Startup folder (`shell:startup`) and from the Start menu.
3. Delete `%AppData%\Floats`.

## Privacy

Floats only switches windows and starts programs. It never reads or sends anything from them. The only network request it makes is to download a website's icon when you add a button for that website.

## License

[MIT](LICENSE)
