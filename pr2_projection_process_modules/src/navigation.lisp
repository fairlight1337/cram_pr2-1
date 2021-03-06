;;; Copyright (c) 2011, Lorenz Moesenlechner <moesenle@in.tum.de>
;;; All rights reserved.
;;; 
;;; Redistribution and use in source and binary forms, with or without
;;; modification, are permitted provided that the following conditions are met:
;;; 
;;;     * Redistributions of source code must retain the above copyright
;;;       notice, this list of conditions and the following disclaimer.
;;;     * Redistributions in binary form must reproduce the above copyright
;;;       notice, this list of conditions and the following disclaimer in the
;;;       documentation and/or other materials provided with the distribution.
;;;     * Neither the name of the Intelligent Autonomous Systems Group/
;;;       Technische Universitaet Muenchen nor the names of its contributors 
;;;       may be used to endorse or promote products derived from this software 
;;;       without specific prior written permission.
;;; 
;;; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
;;; AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
;;; IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
;;; ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
;;; LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
;;; CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
;;; SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
;;; INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
;;; CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
;;; ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
;;; POSSIBILITY OF SUCH DAMAGE.

(in-package :projection-process-modules)

(def-asynchronous-process-module projection-navigation
    ((processing :initform (cpl:make-fluent :value nil)
                 :reader processing)
     (goal :initform (cpl:make-fluent :value nil))))

(defmethod on-run ((process-module projection-navigation))
  (with-slots (processing goal) process-module
    (cpl:whenever (goal)
      (unwind-protect
           (let* ((goal-action (cpl:value goal))
                  (location-designator (desig:reference goal-action)))
             (setf (cpl:value processing) t)
             (execute-as-action
              goal-action
              (lambda ()
                (assert 
                 (prolog:prolog
                  `(and (robot ?robot)
                        (assert (object-pose ?_ ?robot ,(desig:reference location-designator))))))
                (cram-occasions-events:on-event
                 (make-instance 'cram-plan-occasions-events:robot-state-changed))))
             (finish-process-module process-module :designator goal-action))
        (setf (cpl:value goal) nil)
        (setf (cpl:value processing) nil)))))

(defmethod on-input ((process-module projection-navigation) (input desig:action-designator))
  (with-slots (processing goal) process-module
    (assert (not (cpl:value processing)))
    (setf (cpl:value goal) input)))

(defmethod synchronization-fluent ((process-module projection-navigation)
                                   (designator desig:action-designator))
  (cpl-impl:fl-not
   (cpl-impl:fl-or (processing process-module)
                   (processing (get-running-process-module 'projection-manipulation))
                   (processing (get-running-process-module 'projection-ptu))
                   (processing (get-running-process-module 'projection-perception)))))
