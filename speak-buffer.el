;;; speak-buffer.el --- Speak buffer like in a reading App -*- lexical-binding: t -*-

;; Copyright (C) 2025 lorniu <lorniu@gmail.com>

;; Author: lorniu <lorniu@gmail.com>
;; URL: https://github.com/lorniu/speak-buffer.el
;; License: GPL-3.0-or-later
;; Package-Requires: ((emacs "28.1") (go-translate "3.1.0"))
;; Version: 0.1

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; Speak buffer content paragraph by paragraph in Emacs using a TTS engine.
;;
;; Useful for listening to novels/articles, turning Emacs into a reading App.
;;
;; 1. Install:
;;
;;    (use-package speak-buffer
;;     :vc (:url "https://github.com/lorniu/speak-buffer.el")
;;     :config (setq speak-buffer-engine 'edge-tts))
;;
;; 2. Usage:
;;
;;    M-x speak-buffer/speak-buffer-interrupt
;;
;; See README.md of https://github.com/lorniu/speak-buffer.el for more

;;; Code:

(require 'pdd)
(require 'go-translate)

(defgroup speak-buffer nil
  "Speak buffer paragraph by paragraph."
  :group 'external
  :prefix 'speak-buffer-)

(defcustom speak-buffer-language (gt-system-language)
  "The language to use for text-to-speech, it is a symbol like en/zh."
  :type 'symbol)

(defcustom speak-buffer-engine 'native
  "TTS engine used for speaking."
  :type '(choice symbol gt-engine))

(defcustom speak-buffer-interval 0.1
  "Pause seconds after one paragraph."
  :type 'natnum)

(defcustom speak-buffer-prefetch-count 2
  "Number of paragraphs to prefetch for audio."
  :type 'integer)

(defcustom speak-buffer-step-pred #'<
  "A function to determin whether current bounds available."
  :type 'function)

(defcustom speak-buffer-step-action #'speak-buffer--forward-paragraph
  "A function to move forward to next position for new paragraph."
  :type 'function)

(defcustom speak-buffer-final-action nil
  "A function to be called after speak the last paragraph."
  :type '(choice (const nil) function))

(defcustom speak-buffer-text-filter
  (lambda (text) (replace-regexp-in-string "[ \t\n\r]" "" text))
  "A function to cleanup the text in paragraph."
  :type '(choice (const nil) function))

(defcustom speak-buffer-face 'font-lock-warning-face
  "The face used to highlight the current speaking paragraph."
  :type 'face)

(defvar speak-buffer-idle-duration 5)

(defvar speak-buffer-cache-time 60)

(defvar speak-buffer-long-interval-factor 3)

(defvar speak-buffer--task nil)

(defvar speak-buffer--buffer nil)

(defvar speak-buffer-map
  (let ((map (make-sparse-keymap)))
    (define-key map [mouse-3] #'speak-buffer-interrupt)
    (define-key map (kbd "C-g") #'speak-buffer-interrupt)
    map))

(defun speak-buffer--forward-paragraph ()
  "Move point to the next paragraph.

Here not use `forward-paragraph' to avoid too long content in the bounds.
Also make sure that not too short content in the bounds."
  (let ((beg (point)))
    (forward-sentence)
    (skip-syntax-forward ".")
    ;; not too short
    (while (and (char-after) (not (eq (char-after) ?\n))
                (< (- (point) beg) 20))
      (forward-sentence)
      (skip-syntax-forward "."))))

(defun speak-buffer-interrupt ()
  "Interrupt the runing speak buffer task."
  (interactive)
  (when speak-buffer--task
    (pdd-signal speak-buffer--task 'cancel)
    (when (buffer-live-p speak-buffer--buffer)
      (with-current-buffer speak-buffer--buffer
        (dolist (ov (overlays-in (point-min) (point-max)))
          (when (eq (overlay-get ov 'owner) 'speak-buffer)
            (delete-overlay ov)))))
    (setq speak-buffer--task nil)
    (setq speak-buffer--buffer nil)
    (message "Speak buffer interrupted.")))

;;;###autoload
(defun speak-buffer ()
  "Speak current buffer from current point."
  (interactive)
  (speak-buffer-interrupt)
  (setq speak-buffer--buffer (current-buffer))

  (let ((buf speak-buffer--buffer)
        (ov (make-overlay 1 1 nil nil t)))
    (overlay-put ov 'face speak-buffer-face)
    (overlay-put ov 'keymap speak-buffer-map)
    (overlay-put ov 'owner 'speak-buffer)

    (cl-labels
        ((play-from (pos)
           (if-let* ((bounds-list
                      (save-excursion
                        (goto-char pos)
                        (skip-chars-forward " \t\n\r")
                        (setq pos (point))
                        (cl-loop repeat (1+ speak-buffer-prefetch-count)
                                 for beg = (point) then (point)
                                 for end = (save-excursion (funcall speak-buffer-step-action) (point))
                                 while (funcall speak-buffer-step-pred beg end)
                                 collect (cons beg end)
                                 do (funcall speak-buffer-step-action))))
                     (text-list (mapcar
                                 (lambda (bds)
                                   (funcall (or speak-buffer-text-filter #'identity)
                                            (buffer-substring-no-properties (car bds) (cdr bds))))
                                 bounds-list))
                     (current (car bounds-list)) (gt-tts-cache-ttl speak-buffer-cache-time))

               (pdd-chain (car text-list)
                 (lambda (text)
                   (with-current-buffer buf
                     ;; 0. scroll & highlight
                     (when-let* ((win (get-buffer-window buf))
                                 (idle (float-time (or (current-idle-time) 0))))
                       (when (or (not (eq (selected-window) win)) (> idle speak-buffer-idle-duration))
                         (if (not (pos-visible-in-window-p (cdr current) win))
                             ;; scroll only when the buffer is idle and not visible
                             (with-selected-window win (goto-char pos) (recenter t))
                           (goto-char pos))))
                     (move-overlay ov (car current) (cdr current))
                     (redisplay t)
                     ;; 1. prefetch nexts
                     (mapc (lambda (c)
                             (let ((pdd-fail #'ignore))
                               (gt-speech speak-buffer-engine c speak-buffer-language #'ignore)))
                           (cdr text-list))
                     ;; 2. play the current
                     (setq speak-buffer--task (gt-speech speak-buffer-engine text speak-buffer-language))))
                 (lambda (_)
                   (with-current-buffer buf
                     ;; 3. next loop
                     (pdd-cacher-clear gt-tts-cache-store)
                     (move-overlay ov (cdr current) (cdr current))
                     (setq speak-buffer--task
                           (pdd-delay (if (and (numberp speak-buffer-interval) (eq (char-after (cdr current)) ?\n))
                                          ;; more delay time for paragraph end
                                          (* speak-buffer-long-interval-factor speak-buffer-interval)
                                        speak-buffer-interval)
                             (lambda ()
                               ;; post: play next paragraph
                               (with-current-buffer buf (play-from (cdr current)))
                               ;; post: decoupe promise chain
                               nil)))))
                 :fail
                 (lambda (r)
                   (with-current-buffer buf (delete-overlay ov))
                   (setq speak-buffer--task nil)
                   (unless (string-match-p "cancel" (format "%s" r))
                     (message "Speak buffer error: %s" r))
                   (if (consp r) (signal (car r) (cdr r)) (signal 'error r))))

             ;; --- reach the end ---
             (delete-overlay ov)
             (setq speak-buffer--task nil)
             (if (functionp speak-buffer-final-action)
                 (funcall speak-buffer-final-action)
               (message "Speak buffer finished.")))))

      ;; play from current point
      (play-from (point)))))

(provide 'speak-buffer)

;;; speak-buffer.el ends here
