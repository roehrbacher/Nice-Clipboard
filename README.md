# Nice Clipboard

## TL;DR for humans

A clipboard history for [Omarchy](https://omarchy.org) that looks like it ships with it.

<!-- Screenshot: add preview.png to the repo, then replace this comment with: ![Nice Clipboard](preview.png) -->

```bash
omarchy plugin add https://github.com/roehrbacher/Nice-Clipboard --enable
```

It replaces the stock clipboard and keeps your history.

## How you'll use it

**Pins from anywhere.** Pin the items you paste often. Then Alt+Shift+1 to 0 pastes them from anywhere, without opening the popup. Pins take the first keys, in pin order. The newest history items fill the rest.

**Phone and incognito.** With [Flux](https://github.com/bjarneo/flux), copies move between your phone and your computer. Incognito stops new items being saved and pauses phone sync until you turn it off.

**Text from a screenshot.** Copy a screenshot, then copy the text out of it. Recognition runs on your computer, not online.

**Smart items.** Copy an address or GPS coordinates and one click opens them in Maps. A colour code like `#ff8800` shows its colour. Links, email addresses, phone numbers, file paths and GitHub issues like `owner/repo#12` get an open button. A QR code in a copied image is read too: open its link, or copy the Wi-Fi password.

**Paste queue.** Ctrl+click a few items in order, close the popup, and Super+V or Ctrl+V pastes them one after another. Useful when filling in a form.

## Also

- Search supports filters such as `type:image`, `app:firefox` and `today`, and regex.
- A formatted copy from a browser or Docs can be pasted as Markdown.
- Colours follow your Omarchy theme.

## Privacy

History stays on your computer, in `~/.local/share/timon.clipboard/`.

Copies from a password manager are never stored, including Bitwarden and KeePassXC, and neither are copies made with `wl-copy --sensitive`. Incognito stores nothing new and pauses Flux.

Text recognition runs only on your computer.

Once a day, when you open the popup, it asks GitHub whether a newer version exists. You can turn this off in Settings > General.

Feedback in Settings is anonymous. Only the text you type and the plugin version are sent.

## Requirements

Omarchy 4, with `wl-clipboard`.

Optional: `zxing-cpp` or `zbar` for QR codes, `tesseract` and language packs for text in screenshots, `python3` or `pandoc` for Paste as Markdown, and [Flux](https://github.com/bjarneo/flux) for phone sync. The rest works without them.

## Update

Omarchy's own Update menu does not update plugins. For a git install:

```bash
omarchy plugin update timon.clipboard && omarchy restart shell
```

It fetches, shows the changes, and asks first.

## Uninstall

Settings > Uninstall, or:

```bash
omarchy plugin remove timon.clipboard
omarchy restart shell
```

The stock clipboard comes back. To also delete your history: `rm -rf ~/.local/share/timon.clipboard`

## Credit

Built on Omarchy's stock clipboard manager (`shell/plugins/clipboard`, MIT, David Heinemeier Hansson). The UX is modelled on GNOME Clipboard History by Alex Saveau (MIT). No code from that project is used.

See [CHANGELOG.md](CHANGELOG.md) for what changed in each version. Developer notes are in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## License

MIT, see [LICENSE](LICENSE).
