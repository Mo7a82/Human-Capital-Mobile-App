CREATE OR REPLACE PACKAGE xx_hcm_mobile_ws AUTHID CURRENT_USER AS
/* $Header: XX_HCM_MOBILE_WS.pls 120.0.0 2015/03/15 $ */
/*#
 * Services for the Human Capital mobile app: employee profile, absence
 * types, vacation balance, the employee's and manager's vacation worklists,
 * and approving or rejecting a vacation request.
 * Vacation requests themselves are created with the standard
 * HR_PERSON_ABSENCE_API.CREATE_PERSON_ABSENCE service.
 * @rep:scope public
 * @rep:product PER
 * @rep:displayname HCM Mobile Services
 * @rep:category BUSINESS_ENTITY PER_EMPLOYEE
 */

  -- Approval status of a request. It is kept in the absence descriptive
  -- flexfield segment named by g_status_attribute in the package body, so
  -- the mobile app sends P_ATTRIBUTE1 = 'PENDING' when it creates a request.
  c_status_pending  CONSTANT VARCHAR2(30) := 'PENDING';
  c_status_approved CONSTANT VARCHAR2(30) := 'APPROVED';
  c_status_rejected CONSTANT VARCHAR2(30) := 'REJECTED';

  TYPE employee_profile_rec IS RECORD (
    person_id          NUMBER,
    business_group_id  NUMBER,
    assignment_id      NUMBER,
    employee_number    VARCHAR2(30),
    full_name          VARCHAR2(240),
    email_address      VARCHAR2(240),
    work_phone         VARCHAR2(60),
    department_name    VARCHAR2(240),
    position_name      VARCHAR2(240),
    job_name           VARCHAR2(700),
    supervisor_name    VARCHAR2(240),
    hire_date          DATE
  );

  TYPE absence_type_rec IS RECORD (
    absence_attendance_type_id NUMBER,
    name                       VARCHAR2(30),
    absence_category           VARCHAR2(30)
  );
  TYPE absence_type_tbl IS TABLE OF absence_type_rec INDEX BY BINARY_INTEGER;

  TYPE absence_rec IS RECORD (
    absence_attendance_id NUMBER,
    object_version_number NUMBER,
    person_id             NUMBER,
    employee_name         VARCHAR2(240),
    absence_type          VARCHAR2(30),
    date_start            DATE,
    date_end              DATE,
    absence_days          NUMBER,
    comments              VARCHAR2(2000),
    approval_status       VARCHAR2(150)
  );
  TYPE absence_tbl IS TABLE OF absence_rec INDEX BY BINARY_INTEGER;

  /*#
   * Returns the profile of the employee linked to an EBS user: name,
   * employee number, email, work phone, department, position, job and
   * supervisor. Used by the app's My Profile screen right after sign-in.
   * @param p_user_name EBS user name (FND_USER.USER_NAME)
   * @param x_profile Employee profile
   * @param x_return_status S on success, E when the user has no active employee record
   * @param x_message Error message when x_return_status is E
   * @rep:displayname Get Employee Profile
   * @rep:scope public
   * @rep:lifecycle active
   */
  PROCEDURE get_employee_profile (
    p_user_name     IN  VARCHAR2,
    x_profile       OUT NOCOPY employee_profile_rec,
    x_return_status OUT NOCOPY VARCHAR2,
    x_message       OUT NOCOPY VARCHAR2
  );

  /*#
   * Lists the active absence types of a business group, for the vacation
   * type picker on the New Vacation screen.
   * @param p_business_group_id Business group of the employee
   * @param x_absence_types Active absence types
   * @param x_return_status S on success, E on error
   * @param x_message Error message when x_return_status is E
   * @rep:displayname Get Absence Types
   * @rep:scope public
   * @rep:lifecycle active
   */
  PROCEDURE get_absence_types (
    p_business_group_id IN  NUMBER,
    x_absence_types     OUT NOCOPY absence_type_tbl,
    x_return_status     OUT NOCOPY VARCHAR2,
    x_message           OUT NOCOPY VARCHAR2
  );

  /*#
   * Returns the employee's net vacation entitlement on a date, using the
   * accrual plan of the given category the employee is enrolled in.
   * @param p_person_id Employee person ID
   * @param p_effective_date Date of the balance (defaults to today)
   * @param p_accrual_category Accrual plan category, V for vacation
   * @param x_plan_name Name of the accrual plan used
   * @param x_net_entitlement Days the employee can still take
   * @param x_return_status S on success, E when no plan or assignment is found
   * @param x_message Error message when x_return_status is E
   * @rep:displayname Get Vacation Balance
   * @rep:scope public
   * @rep:lifecycle active
   */
  PROCEDURE get_vacation_balance (
    p_person_id        IN  NUMBER,
    p_effective_date   IN  DATE     DEFAULT NULL,
    p_accrual_category IN  VARCHAR2 DEFAULT 'V',
    x_plan_name        OUT NOCOPY VARCHAR2,
    x_net_entitlement  OUT NOCOPY NUMBER,
    x_return_status    OUT NOCOPY VARCHAR2,
    x_message          OUT NOCOPY VARCHAR2
  );

  /*#
   * Lists the employee's own vacation requests with their approval status,
   * newest first, for the My Vacations screen.
   * @param p_person_id Employee person ID
   * @param p_months_back How many months of history to return
   * @param x_absences Vacation requests
   * @param x_return_status S on success, E on error
   * @param x_message Error message when x_return_status is E
   * @rep:displayname Get My Vacations
   * @rep:scope public
   * @rep:lifecycle active
   */
  PROCEDURE get_employee_absences (
    p_person_id     IN  NUMBER,
    p_months_back   IN  NUMBER DEFAULT 12,
    x_absences      OUT NOCOPY absence_tbl,
    x_return_status OUT NOCOPY VARCHAR2,
    x_message       OUT NOCOPY VARCHAR2
  );

  /*#
   * Lists the pending vacation requests of a manager's direct reports,
   * for the approval work list.
   * @param p_manager_person_id Person ID of the manager (assignment supervisor)
   * @param x_absences Pending vacation requests
   * @param x_return_status S on success, E on error
   * @param x_message Error message when x_return_status is E
   * @rep:displayname Get Approval Worklist
   * @rep:scope public
   * @rep:lifecycle active
   */
  PROCEDURE get_manager_worklist (
    p_manager_person_id IN  NUMBER,
    x_absences          OUT NOCOPY absence_tbl,
    x_return_status     OUT NOCOPY VARCHAR2,
    x_message           OUT NOCOPY VARCHAR2
  );

  /*#
   * Approves or rejects a pending vacation request. Only the employee's
   * supervisor can act on it.
   * @param p_absence_attendance_id ID of the vacation request
   * @param p_object_version_number Object version number the app read
   * @param p_manager_person_id Person ID of the approving manager
   * @param p_action APPROVE or REJECT
   * @param p_comments Optional comment saved on the request
   * @param x_object_version_number New object version number
   * @param x_return_status S on success, E on error
   * @param x_message Error message when x_return_status is E
   * @rep:displayname Approve or Reject Vacation
   * @rep:scope public
   * @rep:lifecycle active
   */
  PROCEDURE decide_absence (
    p_absence_attendance_id IN  NUMBER,
    p_object_version_number IN  NUMBER,
    p_manager_person_id     IN  NUMBER,
    p_action                IN  VARCHAR2,
    p_comments              IN  VARCHAR2 DEFAULT NULL,
    x_object_version_number OUT NOCOPY NUMBER,
    x_return_status         OUT NOCOPY VARCHAR2,
    x_message               OUT NOCOPY VARCHAR2
  );

END xx_hcm_mobile_ws;
/
