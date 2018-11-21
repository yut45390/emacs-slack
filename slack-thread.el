;;; slack-thread.el ---                              -*- lexical-binding: t; -*-

;; Copyright (C) 2017  南優也

;; Author: 南優也 <yuyaminami@minamiyuuya-no-MacBook.local>
;; Keywords:

;; This program is free software; you can redistribute it and/or modify
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

;;; Code:

(require 'eieio)
(require 'lui)
(require 'slack-util)
(require 'slack-room)
(require 'slack-channel)
(require 'slack-im)
(require 'slack-message)
(require 'slack-request)

(defvar slack-message-thread-status-keymap)
;; (defconst all-threads-url "https://slack.com/api/subscriptions.thread.getView")
(defconst thread-mark-url "https://slack.com/api/subscriptions.thread.mark")

(defcustom slack-thread-also-send-to-room 'ask
  "Whether a thread message should also be sent to its room.
If nil: don't send to the room.
If `ask': ask the user every time.
Any other non-nil value: send to the room."
  :type '(choice (const :tag "Never send message to the room." nil)
                 (const :tag "Ask the user every time." ask)
                 (const :tag "Always send message to the room." t))
  :group 'slack)

(defclass slack-thread ()
  ((thread-ts :initarg :thread_ts :initform "")
   (messages :initarg :messages :initform '())
   (has-unreads :initarg :has_unreads :initform nil)
   (mention-count :initarg :mention_count :initform 0)
   (reply-count :initarg :reply_count :initform 0)
   (replies :initarg :replies :initform '())
   (active :initarg :active :initform t)
   (root :initarg :root :type slack-message)
   (unread-count :initarg :unread_count :initform 0)
   (last-read :initarg :last_read :initform "0")))

(cl-defmethod slack-thread-messagep ((m slack-message))
  (if (and (oref m thread-ts) (not (slack-message-thread-parentp m)))
      t
    nil))

(cl-defmethod slack-thread-replies ((thread slack-thread) room team &key after-success (cursor nil))
  (let ((ts (oref thread thread-ts)))
    (slack-conversations-replies room ts team
                                 #'(lambda (messages next-cursor)
                                     (when cursor
                                       (setq messages (append (oref thread messages) messages)))
                                     (oset thread messages
                                           (slack-room-sort-messages
                                            (cl-remove-if #'slack-message-thread-parentp
                                                          messages)))
                                     (when (functionp after-success)
                                       (funcall after-success next-cursor)))
                                 cursor)))

(cl-defmethod slack-thread-to-string ((m slack-message) team)
  (slack-if-let* ((thread (oref m thread)))
      (let* ((usernames (mapconcat #'identity
                                   (cl-remove-duplicates
                                    (mapcar #'(lambda (reply)
                                                (slack-user-name
                                                 (plist-get reply :user)
                                                 team))
                                            (oref thread replies))
                                    :test #'string=)
                                   " "))
             (text (format "%s reply from %s"
                           (oref thread reply-count)
                           usernames)))
        (propertize text
                    'face '(:underline t)
                    'keymap slack-message-thread-status-keymap))
    ""))

(cl-defmethod slack-thread-create ((m slack-message) &optional payload)
  (if payload
      (let ((replies (plist-get payload :replies))
            (reply-count (plist-get payload :reply_count))
            (unread-count (plist-get payload :unread_count))
            (last-read (plist-get payload :last_read)))
        (make-instance 'slack-thread
                       :thread_ts (slack-ts m)
                       :root m
                       :replies replies
                       :reply_count (or reply-count 0)
                       :unread_count (or unread-count 1)
                       :last_read last-read))
    (make-instance 'slack-thread
                   :thread_ts (slack-ts m)
                   :root m)))

(cl-defmethod slack-merge ((old slack-thread) new)
  (oset old replies (oref new replies))
  (oset old reply-count (oref new reply-count))
  (oset old unread-count (oref new unread-count)))

(cl-defmethod slack-thread-equal ((thread slack-thread) other)
  (and (string-equal (oref thread thread-ts)
                     (oref other thread-ts))
       (string-equal (oref (oref thread root) channel)
                     (oref (oref other root) channel))))

(cl-defmethod slack-thread-delete-message ((thread slack-thread) message)
  (with-slots (messages reply-count) thread
    (setq messages (cl-remove-if #'(lambda (e)
                                     (string= (slack-ts e)
                                              (slack-ts message)))
                                 messages))
    (setq reply-count (length messages))))

(cl-defmethod slack-thread-marked ((thread slack-thread) payload)
  (let ((unread-count (plist-get payload :unread_count))
        (last-read (plist-get payload :last_read)))
    (oset thread unread-count unread-count)
    (oset thread last-read last-read)))

(provide 'slack-thread)
;;; slack-thread.el ends here
