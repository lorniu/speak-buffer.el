# speak-buffer.el

Speak buffer content paragraph by paragraph in Emacs using a TTS engine.

Useful for listening to novels and articles, turning Emacs into a reading App.

### Features

*   **Asynchronous:** Never blocks Emacs during speech.
*   **Prefetching:** Pre-loads the next paragraphs for smooth, uninterrupted playback.
*   **Configurable:** Delays, faces, paragraph splitting logic, and end-of-buffer actions all are configurable.
*   **Customizable Engine:** Supports any engine from its dependency (`go-translate`), including native OS tools, edge-tts, Google, and ChatGPT.

## Start

Install:
```emacs-lisp
;; By default, native engine is used for speech,
;; That is, `say' in macOS and `powershell' in Windows will be used out of box,
;; For linux, `edge-tts' will be used if installed.

(use-package speak-buffer
  :vc (:url "https://github.com/lorniu/speak-buffer.el"))

;; You can specify engine and custom it for better experience.

(use-package speak-buffer
  :vc (:url "https://github.com/lorniu/speak-buffer.el")
  :config
  ;; See Customization section below
  (setq speak-buffer-language 'zh)
  (setq speak-buffer-engine 'edge-tts)
  (setq gt-tts-edge-tts-speed 1.9))
```

Usage:
*   `M-x speak-buffer`
    Start, restart or stop speaking from the current point. If the cursor is at a speaking paragraph, just stop it, otherwise start a new speaking task from current point.

*   `M-x speak-buffer-interrupt`
    Stop the current speaking task. You can also stop by pressing `C-g`, `SPC` or `right click` on the highlighted region.

*   Adjust the speech dynamically when speaking. Just change the variables, e.g.:
    ```emacs-lisp
    (setq gt-tts-edge-tts-speed 1.9)
    (setq gt-tts-edge-tts-voice "...") ; or `M-x gt-tts-edge-tts-change-voice'
    (setq speak-buffer-engine (gt-google-engine)) ; change engine dynamically
    ```

## Customization

For easy configuration, run `M-x customize-group RET speak-buffer RET`.

Here are some key variables:

| Variable                    | Description                                                                     |
| --------------------------- | ------------------------------------------------------------------------------- |
| `speak-buffer-engine`       | The TTS engine to use (e.g., `'native`, `'edge-tts`, `(gt-google-engine)`).      |
| `speak-buffer-interval`     | Seconds to pause between paragraphs. Default is `0.1`.                          |
| `speak-buffer-final-action` | A function to call when the buffer ends.                                        |
| `speak-buffer-face`         | The face used to highlight the current paragraph.                               |
| `speak-buffer-step-action`  | A function that moves point to define the next paragraph boundary.              |
| `speak-buffer-text-filter`  | A function to clean up paragraph text before sending it to the TTS engine.      |

**Example Configuration:**
```emacs-lisp
;; Use Microsoft Edge's free TTS (pipx install edge-tts)

(setq speak-buffer-engine 'edge-tts)
(setq gt-tts-edge-tts-speed 1.3)
(setq gt-tts-edge-tts-pitch 12)

;; Use TTS engine provided by LLMs

(setq speak-buffer-engine (gt-chatgpt-engine))
(setq speak-buffer-engine (gt-chatgpt-engine :tts-model "tts-1"))

;; When reading is finished, automatically open the next chapter and start speaking
;; This is an example for users of nov.el

(setq speak-buffer-final-action
      (lambda ()
        (when (ignore-errors (nov-next-document))
          (speak-buffer))))

;; Forward example for org mode

(defun speak-buffer--forward-org-heading ()
  (org-forward-heading-same-level 1))

(add-hook 'org-mode-hook
          (lambda ()
            (setq-local speak-buffer-step-action
                        #'speak-buffer--forward-org-heading)))
```

## Miscellaneous

This served as a demonstration of the TTS API usage of package
[go-translate](https://github.com/lorniu/go-translate).

It's so practical and I use it every day. Now I'm glad to share with those people who need it.

For me, it's enough. Feel free to modify and extend it to suit your needs. Also glad to recieve your issues and PRs.

Have a nice day.
