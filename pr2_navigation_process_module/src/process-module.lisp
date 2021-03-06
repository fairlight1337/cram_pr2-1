;;;
;;; Copyright (c) 2010, Lorenz Moesenlechner <moesenle@in.tum.de>
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
;;;     * Neither the name of Willow Garage, Inc. nor the names of its
;;;       contributors may be used to endorse or promote products derived from
;;;       this software without specific prior written permission.
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
;;;

(in-package :pr2-navigation-process-module)

(defparameter *navigation-enabled* t)

(defvar *navp-client* nil)

(defvar *navp-min-angle* (* -135.0 (/ pi 180))
  "When the angle to the goal is greater than *NAVP-MIN-ANGLE*, nav-p
  controller might be used.")
(defvar *navp-max-angle* (* 135.0 (/ pi 180))
  "When the angle to the goal is smaller than *NAVP-MIN-ANGLE*, nav-p
  controller might be used.")
(defvar *navp-max-goal-distance* 2.0
  "When the distance to goal is smaller than *NAVP-GOAL-MAX-DISTANCE*,
  we might use nav-p controller.")
(defvar *xy-goal-tolerance* 0.15)
(defvar *yaw-goal-tolerance* 0.25)

(defun init-pr2-navigation-process-module ()
  (setf *navp-client* (actionlib-lisp:make-simple-action-client
                       "/nav_pcontroller/move_base" "move_base_msgs/MoveBaseAction"))
  (when (roslisp:has-param "~navigation_process_module/navp_min_angle")
    (setf *navp-min-angle* (roslisp:get-param "~navigation_process_module/navp_min_angle")))
  (when (roslisp:has-param "~navigation_process_module/navp_max_angle")
    (setf *navp-max-angle* (roslisp:get-param "~navigation_process_module/navp_max_angle")))
  (when (roslisp:has-param "~navigation_process_module/navp_max_goal_distance")
    (setf *navp-max-goal-distance* (roslisp:get-param "~navigation_process_module/navp_max_goal_distance")))
  (when (roslisp:has-param "~navigation_process_module/xy_goal_tolerance")
    (setf *xy-goal-tolerance* (roslisp:get-param "~navigation_process_module/xy_goal_tolerance")))
  (when (roslisp:has-param "~navigation_process_module/yaw_goal_tolerance")
    (setf *yaw-goal-tolerance* (roslisp:get-param "~navigation_process_module/yaw_goal_tolerance"))))

(roslisp-utilities:register-ros-init-function init-pr2-navigation-process-module)

(defun make-action-goal (pose)
  (actionlib-lisp:make-action-goal-msg *navp-client* target_pose (to-msg pose)))

(defun use-navp? (goal-pose)
  (let* ((pose-in-base (cl-transforms-stamped:transform-pose-stamped
                        *transformer*
                        :pose goal-pose
                        :target-frame *robot-base-frame*
                        :timeout *tf-default-timeout*))
         (goal-dist (cl-transforms:v-norm
                     (cl-transforms:origin pose-in-base)))
         (goal-angle (atan
                      (cl-transforms:y
                       (cl-transforms:origin pose-in-base))
                      (cl-transforms:x
                       (cl-transforms:origin pose-in-base)))))
    (and (< goal-dist *navp-max-goal-distance*)
         (> goal-angle *navp-min-angle*)
         (< goal-angle *navp-max-angle*))))

(defun goal-reached? (goal-pose)
  (let* ((pose-in-base (cl-transforms-stamped:transform-pose-stamped
                        *transformer*
                        :pose goal-pose :target-frame *robot-base-frame*
                        :timeout *tf-default-timeout*))
         (goal-dist (cl-transforms:v-norm
                     (cl-transforms:origin pose-in-base)))
         (goal-angle (second
                      (multiple-value-list
                          (cl-transforms:quaternion->axis-angle
                           (cl-transforms:orientation pose-in-base))))))
    (cond ((and (> goal-dist *xy-goal-tolerance*)
                (> (abs goal-angle) *yaw-goal-tolerance*))
           (roslisp:ros-warn
            (pr2-nav process-module)
            "Goal not reached. Linear distance: ~a, angular distance: ~a"
            goal-dist goal-angle)
           nil)
          (t t))))

(defun call-nav-action (client desig)
  (let* ((goal-pose (reference desig))
         (goal-pose-in-fixed-frame
           (cl-transforms-stamped:transform-pose-stamped
            *transformer*
            :pose goal-pose
            :target-frame *fixed-frame*
            :timeout *tf-default-timeout*
            :use-current-ros-time t)))
    (roslisp:publish (roslisp:advertise "/ppp" "geometry_msgs/PoseStamped")
                     (to-msg goal-pose-in-fixed-frame))
    (actionlib-lisp:wait-for-server client)
    (multiple-value-bind (result status)
        (actionlib-lisp:send-goal-and-wait
         client (make-action-goal goal-pose-in-fixed-frame)
         10.0 10.0)
      (declare (ignorable result status))
      (roslisp:ros-info (pr2-nav process-module) "Nav action finished.")
      (unless (goal-reached? (copy-pose-stamped
                              goal-pose-in-fixed-frame
                              :stamp 0))
        (cpl:fail 'location-not-reached-failure
                  :location desig)))))

(def-process-module pr2-navigation-process-module (goal)
  (when *navigation-enabled*
    (unwind-protect
         (progn
           (roslisp:ros-info (pr2-nav process-module) "Using nav-pcontroller.")
           (call-nav-action *navp-client* (reference goal)))
      (roslisp:ros-info (pr2-nav process-module) "Navigation finished.")
      (cram-occasions-events:on-event
       (make-instance 'cram-plan-occasions-events:robot-state-changed)))))
