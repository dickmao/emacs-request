;;; test-request.el --- Tests for request.el

;; Copyright (C) 2012 Takafumi Arakaki

;; Author: Takafumi Arakaki <aka.tkf at gmail.com>

;; This file is NOT part of GNU Emacs.

;; test-request.el is free software: you can redistribute it
;; and/or modify it under the terms of the GNU General Public License
;; as published by the Free Software Foundation, either version 3 of
;; the License, or (at your option) any later version.

;; test-request.el is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with test-request.el.
;; If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;;

;;; Code:

(eval-when-compile (require 'cl))
(require 'json)
(require 'request-testing)

(let ((level (getenv "EL_REQUEST_MESSAGE_LEVEL")))
  (when (and level (not (equal level "")))
    (setq request-message-level (intern level))))
(setq request-log-level request-message-level)

(let ((backend (getenv "EL_REQUEST_BACKEND")))
  (when (and backend (not (equal backend "")))
    (setq request-backend (intern backend))
    (message "Using request-backend = %S" request-backend)))

(let ((no-capture (getenv "EL_REQUEST_NO_CAPTURE_MESSAGE")))
  (when (and no-capture (not (equal no-capture "")))
    (setq request-testing-capture-message nil)))

;; Quick snippets for interactive testing:
;;   (setq request-backend 'curl)
;;   (setq request-backend 'url-retrieve)
;;   (setq request-log-level 'blather)
;;   (setq request-log-level -1)



;;; GET

(request-deftest request-simple-get ()
  (request-testing-with-response-slots
      (request-testing-sync "report/some-path"
                            :parser 'json-read)
    (should done-p)
    (should (equal status-code 200))
    (should (equal (assoc-default 'path data) "some-path"))
    (should (equal (assoc-default 'method data) "GET"))))

(request-deftest request-get-with-args ()
  (request-testing-with-response-slots
      (request-testing-sync "report/some-path?a=1&b=2"
                            :parser 'json-read)
    (should (equal status-code 200))
    (should (equal (request-testing-sort-alist (assoc-default 'args data))
                   '((a . "1") (b . "2"))))
    (should (equal (assoc-default 'path data) "some-path"))))

(defun request-testing-assert-redirected-to (response path)
  (request-testing-with-response-slots
      response
    (if (and noninteractive (eq request-backend 'url-retrieve))
        ;; `url-retrieve' adds %0D to redirection path when the test
        ;; is run in noninteractive environment.
        ;; probably it's a bug in `url-retrieve'...
        (progn
          (should (string-prefix-p (request-testing-url "report" path) url))
          (should (string-prefix-p path (assoc-default 'path data))))
      (should (equal (request-testing-url "report" path) url))
      (should (equal (assoc-default 'path data) path)))
    (should (equal status-code 200))
    (should (equal (assoc-default 'method data) "GET"))))

(request-deftest request-get-simple-redirection ()
  (let ((response (request-testing-sync "redirect/redirect/report/some-path"
                                        :parser 'json-read)))
    (request-testing-assert-redirected-to response "some-path")))

(request-deftest request-get-broken-redirection ()
  "Relative Location must be treated gracefully, even if it is not
correct according to RFC 2616.
See also:
* RFC 2616 Section 14.30: http://tools.ietf.org/html/rfc2616#section-14.30
* GNU bug report #12374: http://debbugs.gnu.org/cgi/bugreport.cgi?bug=12374
"
  :backends (curl)
  (let ((response (request-testing-sync "broken_redirect/report/some-path"
                                        :parser 'json-read)))
    (request-testing-assert-redirected-to response "some-path")))

(request-deftest request-get-code-success ()
  (loop for code in (nconc (loop for c from 200 to 207 collect c)
                           (list 226))
        do (request-testing-with-response-slots
               (request-testing-sync (format "code/%d" code)
                                     :parser 'ignore)
             (should-not error-thrown)
             (should (equal status-code code)))))

(request-deftest request-get-code-client-error ()
  (loop for code in (loop for c from 400 to 418
                          ;; 401: Unauthorized
                          ;;      `url-retrieve' pops prompt.
                          ;;      FIXME: find a way to test in a batch mode.
                          ;; 402: Payment Required
                          ;;      "Reserved for future use."
                          ;;      So it's OK to ignore this code?
                          ;; 407: Proxy Authentication Required
                          ;;      FIXME: how to support this?
                          unless (member c '(401 402 407))
                          collect c)
        do (request-testing-with-response-slots
               (request-testing-sync (format "code/%d" code)
                                     :parser 'ignore)
             (should (equal error-thrown `(error . (http ,code))))
             (should (equal status-code code)))))

(request-deftest request-get-code-server-error ()
  (loop for code in (loop for c from 500 to 510
                          ;; flask does not support them:
                          unless (member c '(506 508 509))
                          collect c)
        do (request-testing-with-response-slots
               (request-testing-sync (format "code/%d" code)
                                     :parser 'ignore)
             (should (equal error-thrown `(error . (http ,code))))
             (should (equal status-code code)))))


;;; POST

(request-deftest request-simple-post ()
  (request-testing-with-response-slots
      (request-testing-sync "report/some-path"
                            :type "POST" :data "key=value"
                            :parser 'json-read)
    (should (equal status-code 200))
    (should (equal (assoc-default 'path data) "some-path"))
    (should (equal (assoc-default 'method data) "POST"))
    (should (equal (assoc-default 'form data) '((key . "value"))))))

(request-deftest request-post-multibytes ()
  (request-testing-with-response-slots
      (request-testing-sync "report/some-path"
                            :type "POST"
                            :data '(("鍵" . "値"))
                            :parser (lambda ()
                                      (let ((json-key-type 'string))
                                        (json-read))))
    (should (equal status-code 200))
    (should-not error-thrown)
    (should (equal (assoc-default "path"   data) "some-path"))
    (should (equal (assoc-default "method" data) "POST"))
    (should (equal (assoc-default "form"   data) '(("鍵" . "値"))))))

(request-deftest request-post-files/simple-buffer ()
  :backends (curl)
  (with-current-buffer (get-buffer-create " *request-test-temp*")
    (erase-buffer)
    (insert "BUFFER CONTENTS"))
  (request-testing-with-response-slots
      (request-testing-sync
       "report/some-path"
       :type "POST"
       :files `(("name" . ,(get-buffer-create " *request-test-temp*")))
       :parser 'json-read)
    (should (equal status-code 200))
    (should (equal (assoc-default 'path data) "some-path"))
    (should (equal (assoc-default 'method data) "POST"))
    (should (= (length (assoc-default 'files data)) 1))
    (should (equal
             (request-testing-sort-alist (elt (assoc-default 'files data) 0))
             '((data . "BUFFER CONTENTS")
               (filename . " *request-test-temp*")
               (name . "name"))))))

(request-deftest request-post-files/simple-file ()
  :backends (curl)
  :tempfiles (tf)
  (with-temp-buffer
    (erase-buffer)
    (insert "BUFFER CONTENTS")
    (write-region (point-min) (point-max) tf nil 'silent))
  (request-testing-with-response-slots
      (request-testing-sync
       "report/some-path"
       :type "POST"
       :files `(("name" . ,tf))
       :parser 'json-read)
    (should (equal status-code 200))
    (should (equal (assoc-default 'path data) "some-path"))
    (should (equal (assoc-default 'method data) "POST"))
    (should (= (length (assoc-default 'files data)) 1))
    (should (equal
             (request-testing-sort-alist (elt (assoc-default 'files data) 0))
             `((data . "BUFFER CONTENTS")
               (filename . ,(file-name-nondirectory tf))
               (name . "name"))))))

(request-deftest request-post-files/standard-buffer ()
  :backends (curl)
  (with-current-buffer (get-buffer-create " *request-test-temp*")
    (erase-buffer)
    (insert "BUFFER CONTENTS"))
  (request-testing-with-response-slots
      (request-testing-sync
       "report/some-path"
       :type "POST"
       :files `(("name" .
                 ("filename"
                  :buffer ,(get-buffer-create " *request-test-temp*"))))
       :parser 'json-read)
    (should (equal status-code 200))
    (should (equal (assoc-default 'path data) "some-path"))
    (should (equal (assoc-default 'method data) "POST"))
    (should (= (length (assoc-default 'files data)) 1))
    (should (equal
             (request-testing-sort-alist (elt (assoc-default 'files data) 0))
             '((data . "BUFFER CONTENTS")
               (filename . "filename")
               (name . "name"))))))

(request-deftest request-post-files/standard-file ()
  :backends (curl)
  :tempfiles (tf)
  (with-temp-buffer
    (erase-buffer)
    (insert "BUFFER CONTENTS")
    (write-region (point-min) (point-max) tf nil 'silent))
  (request-testing-with-response-slots
      (request-testing-sync
       "report/some-path"
       :type "POST"
       :files `(("name" . ("filename" :file ,tf)))
       :parser 'json-read)
    (should (equal status-code 200))
    (should (equal (assoc-default 'path data) "some-path"))
    (should (equal (assoc-default 'method data) "POST"))
    (should (= (length (assoc-default 'files data)) 1))
    (should (equal
             (request-testing-sort-alist (elt (assoc-default 'files data) 0))
             '((data . "BUFFER CONTENTS")
               (filename . "filename")
               (name . "name"))))))

(request-deftest request-post-files/standard-data ()
  :backends (curl)
  (request-testing-with-response-slots
      (request-testing-sync
       "report/some-path"
       :type "POST"
       :files '(("name" . ("data.csv" :data "1,2,3\n4,5,6\n")))
       :parser 'json-read)
    (should (equal status-code 200))
    (should (equal (assoc-default 'path data) "some-path"))
    (should (equal (assoc-default 'method data) "POST"))
    (should (= (length (assoc-default 'files data)) 1))
    (should (equal
             (request-testing-sort-alist (elt (assoc-default 'files data) 0))
             '((data . "1,2,3\n4,5,6\n")
               (filename . "data.csv")
               (name . "name"))))))


;;; PUT

(request-deftest request-simple-put ()
  (request-testing-with-response-slots
      (request-testing-sync "report/some-path"
                            :type "PUT" :data "dummy-data"
                            :headers '(("Content-Type" . "text/plain"))
                            :parser 'json-read)
    (should (equal status-code 200))
    (should (equal (assoc-default 'path data) "some-path"))
    (should (equal (assoc-default 'method data) "PUT"))
    (should (equal (assoc-default 'data data) "dummy-data"))))

(request-deftest request-simple-put-json ()
  (request-testing-with-response-slots
      (request-testing-sync "report/some-path"
                            :type "PUT" :data "{\"a\": 1, \"b\": 2, \"c\": 3}"
                            :headers '(("Content-Type" . "application/json"))
                            :parser 'json-read)
    (should (equal status-code 200))
    (should (equal (assoc-default 'path data) "some-path"))
    (should (equal (assoc-default 'method data) "PUT"))
    (should (equal (request-testing-sort-alist (assoc-default 'json data))
                   '((a . 1) (b . 2) (c . 3))))))


;;; DELETE

(request-deftest request-simple-delete ()
  (request-testing-with-response-slots
      (request-testing-sync "report/some-path"
                            :type "DELETE"
                            :parser 'json-read)
    (should (equal status-code 200))
    (should (equal (assoc-default 'path data) "some-path"))
    (should (equal (assoc-default 'method data) "DELETE"))))


;;; Abort

(request-deftest request-abort-simple ()
  (let (called)
    (request-testing-with-response-slots
        (request-testing-async "sleep/0.5"
                               :complete (lambda (&rest args)
                                           (push args called))
                               :parser 'json-read)
      (let ((process (get-buffer-process -buffer)))
        (loop repeat 30
              when (request-testing-process-live-p process) return nil
              do (sleep-for 0.1)
              finally (error "Timeout: failed to check process is started."))

        (should-not symbol-status)
        (should-not done-p)
        (should (request-testing-process-live-p process))

        (request-abort response)
        (loop repeat 30
              when called return nil
              do (sleep-for 0.1)
              finally (error "Timeout: failed to check process is aborted."))

        (should (equal symbol-status 'abort))
        (should done-p)
        (should-not (request-testing-process-live-p process))))

    (should (= (length called) 1))
    (destructuring-bind (&key data symbol-status error-thrown response)
        (car called)
      (should-not data)
      (should (eq symbol-status 'abort))
      (should error-thrown)
      (should response))))


;;; Parse error

(request-deftest request-parse-error-simple ()
  (request-testing-with-response-slots
      (request-testing-sync "report/some-path"
                            :parser (lambda () (error "Bad parser!")))
    (should done-p)
    (should (equal symbol-status 'parse-error))
    (should (equal error-thrown '(error . ("Bad parser!"))))))


;;; Cookie

(request-deftest request-simple-cookie ()
  :tempfiles (request--curl-cookie-jar)
  (request-testing-with-response-slots
      (request-testing-sync "cookies/set"
                            :params '((cookie-name . "cookie-value"))
                            :parser 'json-read)
    (should (equal status-code 200))
    (unless (and noninteractive (eq request-backend 'url-retrieve))
      ;; *Sometimes* it fails.  As from-cookies\r is returned,
      ;; it looks like url.el fails to clean tailing \r in the
      ;; header fields.
      (should (equal (assoc-default 'path data) "from-cookies"))
      (should (equal (assoc-default 'cookie-name (assoc-default 'cookies data))
                     "cookie-value"))
      (should (equal (request-cookie-string "127.0.0.1" "/")
                     "cookie-name=cookie-value")))
    (should (equal (assoc-default 'method data) "GET"))))

(request-deftest request-multiple-cookies ()
  :tempfiles (request--curl-cookie-jar)
  (request-testing-with-response-slots
      (request-testing-sync "cookies/set"
                            :params '(("a" . "1") ("b" . "2"))
                            :parser 'json-read)
    (should (equal status-code 200))
    (unless (and noninteractive (eq request-backend 'url-retrieve))
      ;; See `request-simple-cookie'.
      (should (equal (assoc-default 'path data) "from-cookies"))
      (should (equal (request-testing-sort-alist (assoc-default 'cookies data))
                     '((a . "1") (b . "2"))))
      (should (member (request-cookie-string "127.0.0.1" "/") '("a=1; b=2"
                                                                "b=2; a=1"))))
    (should (equal (assoc-default 'method data) "GET"))))

(defun request-testing-assert-username-is (username)
  (request-testing-with-response-slots
      (request-testing-sync "report/some-path"
                            :parser 'json-read)
    (should (equal status-code 200))
    (should (equal (assoc-default 'path data) "some-path"))
    (should (equal (assoc-default 'username data) username))
    (should (equal (assoc-default 'method data) "GET"))))

(request-deftest request-session-cookie ()
  :backends (curl)
  :tempfiles (request--curl-cookie-jar)
  (request-testing-assert-username-is nil)
  ;; login
  (request-testing-with-response-slots
      (request-testing-sync "login"
                            :data "username=gooduser&password=goodpass"
                            :type "POST"
                            :parser 'json-read)
    (should (equal status-code 200))
    (should (equal (assoc-default 'path data) "from-login"))
    (should (equal (assoc-default 'username data) "gooduser"))
    (should (equal (assoc-default 'method data) "POST")))
  ;; check login state
  (request-testing-assert-username-is "gooduser")
  ;; logout
  (request-testing-with-response-slots
      (request-testing-sync "logout"
                            :parser 'json-read)
    (should (equal status-code 200))
    (should (equal (assoc-default 'path data) "from-logout"))
    (should (equal (assoc-default 'username data) nil))
    (should (equal (assoc-default 'method data) "GET")))
  ;; check login state
  (request-testing-assert-username-is nil))


;;; `request-backend'-independent tests

;; Following tests does not depend on the value of `request-backend'.
;; Move them to another file when this test suite get bigger.

(ert-deftest request--urlencode-alist/simple ()
  (should (equal (request--urlencode-alist '((a . "1") (b . "2")))
                 "a=1&b=2")))

(ert-deftest request--urlencode-alist/hexified ()
  ;; Down-case string so that the test passes in Emacs 24.2.
  ;; In Emacs 24.2 hexadecimal digits were lower case while it's
  ;; upper case in 24.3.
  ;; See: http://bzr.savannah.gnu.org/lh/emacs/trunk/revision/108173
  (should (equal (downcase
                  (request--urlencode-alist
                   '(("key with space" . "*evil* !values!"))))
                 "key%20with%20space=%2aevil%2a%20%21values%21")))

(ert-deftest request--curl-preprocess/no-redirects ()
  (with-temp-buffer
    (erase-buffer)
    (insert "\
HTTP/1.0 200 OK\r
Content-Type: application/json\r
Content-Length: 88\r
Server: Werkzeug/0.8.1 Python/2.7.2+\r
Date: Sat, 15 Dec 2012 23:04:26 GMT\r
\r
RESPONSE-BODY")
    (insert "\n(:num-redirects 0 :url-effective \"DUMMY-URL\")")
    (let ((info (request--curl-preprocess)))
      (should (equal (buffer-string)
                     "\
HTTP/1.0 200 OK
Content-Type: application/json
Content-Length: 88
Server: Werkzeug/0.8.1 Python/2.7.2+
Date: Sat, 15 Dec 2012 23:04:26 GMT

RESPONSE-BODY"))
      (should (equal info
                     (list :num-redirects 0
                           :url-effective "DUMMY-URL"
                           :redirects nil
                           :cookies nil
                           :version "1.0" :code 200))))))

(ert-deftest request--curl-preprocess/two-redirects ()
  (with-temp-buffer
    (erase-buffer)
    (insert "\
HTTP/1.0 302 FOUND\r
Content-Type: text/html; charset=utf-8\r
Content-Length: 257\r
Location: http://example.com/redirect/a/b\r
Server: Werkzeug/0.8.1 Python/2.7.2+\r
Date: Sat, 15 Dec 2012 23:04:26 GMT\r
\r
HTTP/1.0 302 FOUND\r
Content-Type: text/html; charset=utf-8\r
Content-Length: 239\r
Location: http://example.com/a/b\r
Server: Werkzeug/0.8.1 Python/2.7.2+\r
Date: Sat, 15 Dec 2012 23:04:26 GMT\r
\r
HTTP/1.0 200 OK\r
Content-Type: application/json\r
Content-Length: 88\r
Server: Werkzeug/0.8.1 Python/2.7.2+\r
Date: Sat, 15 Dec 2012 23:04:26 GMT\r
\r
RESPONSE-BODY")
    (insert "\n(:num-redirects 2 :url-effective \"DUMMY-URL\")")
    (let ((info (request--curl-preprocess)))
      (should (equal (buffer-string)
                     "\
HTTP/1.0 200 OK
Content-Type: application/json
Content-Length: 88
Server: Werkzeug/0.8.1 Python/2.7.2+
Date: Sat, 15 Dec 2012 23:04:26 GMT

RESPONSE-BODY"))
      (should (equal info
                     (list :num-redirects 2
                           :url-effective "DUMMY-URL"
                           :redirects '("http://example.com/a/b"
                                        "http://example.com/redirect/a/b")
                           :cookies nil
                           :version "1.0" :code 200))))))

(ert-deftest request--curl-preprocess/100 ()
  (with-temp-buffer
    (erase-buffer)
    (insert "\
HTTP/1.1 100 Continue\r
\r
HTTP/1.1 200 OK\r
Content-Type: application/json\r
Date: Wed, 19 Dec 2012 16:51:53 GMT\r
Server: gunicorn/0.13.4\r
Content-Length: 492\r
Connection: keep-alive\r
\r
RESPONSE-BODY")
    (insert "\n(:num-redirects 0 :url-effective \"DUMMY-URL\")")
    (let ((info (request--curl-preprocess)))
      (should (equal (buffer-string)
                     "\
HTTP/1.1 200 OK
Content-Type: application/json
Date: Wed, 19 Dec 2012 16:51:53 GMT
Server: gunicorn/0.13.4
Content-Length: 492
Connection: keep-alive

RESPONSE-BODY"))
      (should (equal info
                     (list :num-redirects 0
                           :url-effective "DUMMY-URL"
                           :redirects nil
                           :cookies nil
                           :version "1.1" :code 200))))))

(ert-deftest request--curl-preprocess/cookies ()
  (with-temp-buffer
    (erase-buffer)
    (insert "\
HTTP/1.1 302 Found\r
Content-Length: 0\r
Content-Type: text/html; charset=UTF-8\r
Location: /\r
Server: TornadoServer/2.2\r
Set-Cookie: username=Nzk2ZmU; expires=Tue, 15 Jan 2013 22:50:19 GMT; Path=/\r
\r
")
    (insert "\n(:num-redirects 0 :url-effective \"DUMMY-URL\")")
    (let ((info (request--curl-preprocess)))
      (should (equal (buffer-string)
                     "\
HTTP/1.1 302 Found
Content-Length: 0
Content-Type: text/html; charset=UTF-8
Location: /
Server: TornadoServer/2.2
Set-Cookie: username=Nzk2ZmU; expires=Tue, 15 Jan 2013 22:50:19 GMT; Path=/

"))
      (should (equal info
                     (list :num-redirects 0
                           :url-effective "DUMMY-URL"
                           :redirects nil
                           :cookies '(("username" . "Nzk2ZmU"))
                           :version "1.1" :code 302))))))

(ert-deftest request--netscape-cookie-parse ()
  (with-temp-buffer
    (erase-buffer)
    (insert "\
# Netscape HTTP Cookie File
# http://curl.haxx.se/rfc/cookie_spec.html
# This file was generated by libcurl! Edit at your own risk.

#HttpOnly_127.0.0.1	FALSE	/	FALSE	0	session	\"Jm7AXQMIE\"
127.0.0.1	FALSE	/	FALSE	0	key1	value1
127.0.0.1	FALSE	/	FALSE	0	key2	value2
")
    (should (equal (request--netscape-cookie-parse)
                   '(("127.0.0.1" nil "/" nil 0 "key1" "value1")
                     ("127.0.0.1" nil "/" nil 0 "key2" "value2"))))))

(provide 'test-request)

;;; test-request.el ends here
