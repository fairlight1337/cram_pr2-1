;;; Copyright (c) 2013, Georg Bartels <georg.bartels@cs.uni-bremen.de>
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

(in-package :pr2-manip-pm)

(defvar *left-feature-constraints-config-pub* nil)
(defvar *left-feature-constraints-command-pub* nil)

(defvar *controller-state-subscriber* nil)
(defvar *controller-state-active-fluent* nil)

(defun init-feature-constraints-controller ()
  (setf *left-feature-constraints-command-pub*
        (roslisp:advertise
         "/left_arm_feature_controller/constraint_command"
         "constraint_msgs/ConstraintCommand"))
  (setf *left-feature-constraints-config-pub*
        (roslisp:advertise
         "/left_arm_feature_controller/constraint_config"
         "constraint_msgs/ConstraintConfig"))
  (setf *controller-state-active-fluent*
        (cram-language:make-fluent :name :feature-controller-state-fluent
                                   :allow-tracing nil))
  (setf *controller-state-subscriber*
        (roslisp:subscribe
         "/left_arm_feature_controller/constraint_state"
         "constraint_msgs/ConstraintState"
         #'feature-constraints-controller-state-callback)))

(register-ros-init-function init-feature-constraints-controller)

(defmethod feature-constraints-controller-state-callback
    ((msg (eql 'constraint_msgs-msg:ConstraintState)))
  (roslisp:with-fields (weights) msg
    (let ((max-weight (loop for i from 0 below (length weights)
                            for weight = (elt weights i)
                            maximizing weight into max-weight
                            finally (return max-weight))))
      (cond ((< max-weight 1.0)
             ;; All weights are < 1.0, meaning that all constraints are
             ;; satisfied.
             (setf (cram-language:value *controller-state-active-fluent*) T)
             (cram-language:pulse *controller-state-active-fluent*))
            (t (setf (cram-language:value
                      *controller-state-active-fluent*) nil))))))

(defun wait-for-controller (&optional (timeout nil))
  (cram-language:wait-for *controller-state-active-fluent* :timeout timeout))

(defun send-constraints-config (constraints)
  ;; TODO(Georg): differentiate arms
  (roslisp:publish
   *left-feature-constraints-config-pub*
   (cram-feature-constraints:feature-constraints->config-msg constraints)))

(defun send-constraints-command (constraints)
  ;; TODO(Georg): differentiate arms
  (roslisp:publish
   *left-feature-constraints-command-pub*
   (cram-feature-constraints:feature-constraints->command-msg constraints)))

(defun grasp-ketchup-bottle ()
  ;; start up tf-relays -- a bit hacky because we circumvent time travel problems
;  (set-up-tf-relays)
  (let* ((ketchup-main-axis
           (make-instance
            'cram-feature-constraints:geometric-feature
            :name "main axis ketchup bottle"
            :frame-id "/ketchup_frame"
            :feature-type 'cram-feature-constraints:line
            :feature-position (cl-transforms:make-3d-vector 0.0 0.0 0.0)
            :feature-direction (cl-transforms:make-3d-vector 0.0 0.0 0.1)
            :contact-direction (cl-transforms:make-3d-vector 0.1 0.0 0.0)))
         ;; using pointing-3d removes the need for this 'virtual feature'
         (ketchup-plane
           (make-instance
            'cram-feature-constraints:geometric-feature
            :name "plane through ketchup bottle"
            :frame-id "/ketchup_frame"
            :feature-type 'cram-feature-constraints:plane
            :feature-position (cl-transforms:make-3d-vector 0.0 0.0 0.0)
            :feature-direction (cl-transforms:make-3d-vector 0.0 0.0 0.1)
            :contact-direction (cl-transforms:make-3d-vector 0.1 0.0 0.0)))
         (gripper-plane
           (make-instance
            'cram-feature-constraints:geometric-feature
            :name "left gripper plane"
            :frame-id "/l_gripper_tool_frame"
            :feature-type 'cram-feature-constraints:plane
            :feature-position (cl-transforms:make-3d-vector 0.0 0.0 0.0)
            :feature-direction (cl-transforms:make-3d-vector 0.0 0.0 0.1)
            :contact-direction (cl-transforms:make-3d-vector 0.1 0.0 0.0)))
         (gripper-main-axis
           (make-instance
            'cram-feature-constraints:geometric-feature
            :name "left gripper main axis"
            :frame-id "/l_gripper_tool_frame"
            :feature-type 'cram-feature-constraints:line
            :feature-position (cl-transforms:make-3d-vector 0.0 0.0 0.0)
            :feature-direction (cl-transforms:make-3d-vector 0.1 0.0 0.0)
            :contact-direction (cl-transforms:make-3d-vector 0.0 0.1 0.0)))
         (gripper-vertical-constraint
           (make-instance
            'cram-feature-constraints:feature-constraint
            :name "gripper vertical constraint"
            :feature-function "perpendicular"
            :tool-feature gripper-plane
            :world-feature ketchup-main-axis
            :lower-boundary 0.95
            :upper-boundary 1.0
            :weight 1.0
            :maximum-velocity 0.1
            :minimum-velocity -0.1))
         (gripper-pointing-at-ketchup
           (make-instance
            'cram-feature-constraints:feature-constraint
            :name "gripper pointing at ketchup"
            :feature-function "pointing_at"
            :tool-feature gripper-main-axis
            :world-feature ketchup-plane
            :lower-boundary -0.1
            :upper-boundary 0.1
            :weight 1.0
            :maximum-velocity 0.1
            :minimum-velocity -0.1))
         (gripper-height-constraint
           (make-instance
            'cram-feature-constraints:feature-constraint
            :name "gripper height constraint"
            :feature-function "height"
            :tool-feature gripper-plane
            :world-feature ketchup-plane
            :lower-boundary -0.05
            :upper-boundary 0.05
            :weight 1.0
            :maximum-velocity 0.1
            :minimum-velocity -0.1))
         (gripper-distance-constraint
          (make-instance
            'cram-feature-constraints:feature-constraint
            :name "gripper height constraint"
            :feature-function "distance"
            :tool-feature gripper-plane
            :world-feature ketchup-plane
            :lower-boundary 0.01
            :upper-boundary 0.02
            :weight 1.0
            :maximum-velocity 0.1
            :minimum-velocity -0.1)))
         (list
           gripper-vertical-constraint
           gripper-pointing-at-ketchup
           gripper-height-constraint
           gripper-distance-constraint)))