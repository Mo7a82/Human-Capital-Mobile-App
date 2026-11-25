CREATE OR REPLACE PACKAGE BODY xx_hcm_mobile_ws AS
/* $Header: XX_HCM_MOBILE_WS.plb 120.0.0 2015/03/15 $ */

  -- The approval status of a vacation request lives in ATTRIBUTE1 of the
  -- absence descriptive flexfield (PER_ABSENCE_ATTENDANCES). If your instance
  -- already uses ATTRIBUTE1, change the column in the queries and in
  -- decide_absence below, and send that P_ATTRIBUTEn from the app instead.

  c_success CONSTANT VARCHAR2(1) := 'S';
  c_error   CONSTANT VARCHAR2(1) := 'E';

  -- ---------------------------------------------------------------------------
  -- Helpers
  -- ---------------------------------------------------------------------------

  PROCEDURE set_error (
    x_return_status OUT NOCOPY VARCHAR2,
    x_message       OUT NOCOPY VARCHAR2,
    p_message       IN  VARCHAR2
  ) IS
  BEGIN
    x_return_status := c_error;
    x_message       := SUBSTR(p_message, 1, 2000);
  END set_error;

  -- Primary assignment of an employee on a date.
  PROCEDURE get_primary_assignment (
    p_person_id         IN  NUMBER,
    p_effective_date    IN  DATE,
    x_assignment_id     OUT NUMBER,
    x_payroll_id        OUT NUMBER,
    x_business_group_id OUT NUMBER
  ) IS
  BEGIN
    SELECT paf.assignment_id, paf.payroll_id, paf.business_group_id
      INTO x_assignment_id, x_payroll_id, x_business_group_id
      FROM per_all_assignments_f paf
     WHERE paf.person_id = p_person_id
       AND paf.primary_flag = 'Y'
       AND paf.assignment_type = 'E'
       AND p_effective_date BETWEEN paf.effective_start_date AND paf.effective_end_date;
  END get_primary_assignment;

  -- ---------------------------------------------------------------------------
  -- get_employee_profile
  -- ---------------------------------------------------------------------------

  PROCEDURE get_employee_profile (
    p_user_name     IN  VARCHAR2,
    x_profile       OUT NOCOPY employee_profile_rec,
    x_return_status OUT NOCOPY VARCHAR2,
    x_message       OUT NOCOPY VARCHAR2
  ) IS
    l_today DATE := TRUNC(SYSDATE);
  BEGIN
    SELECT ppf.person_id,
           ppf.business_group_id,
           paf.assignment_id,
           ppf.employee_number,
           ppf.full_name,
           NVL(ppf.email_address, fu.email_address),
           (SELECT ph.phone_number
              FROM per_phones ph
             WHERE ph.parent_id = ppf.person_id
               AND ph.parent_table = 'PER_ALL_PEOPLE_F'
               AND ph.phone_type = 'W1'
               AND l_today BETWEEN ph.date_from AND NVL(ph.date_to, l_today)
               AND ROWNUM = 1),
           hou.name,
           pos.name,
           pj.name,
           sup.full_name,
           ppf.original_date_of_hire
      INTO x_profile.person_id,
           x_profile.business_group_id,
           x_profile.assignment_id,
           x_profile.employee_number,
           x_profile.full_name,
           x_profile.email_address,
           x_profile.work_phone,
           x_profile.department_name,
           x_profile.position_name,
           x_profile.job_name,
           x_profile.supervisor_name,
           x_profile.hire_date
      FROM fnd_user                  fu,
           per_all_people_f          ppf,
           per_all_assignments_f     paf,
           hr_all_organization_units hou,
           hr_all_positions_f        pos,
           per_jobs                  pj,
           per_all_people_f          sup
     WHERE fu.user_name = UPPER(p_user_name)
       AND l_today BETWEEN fu.start_date AND NVL(fu.end_date, l_today)
       AND ppf.person_id = fu.employee_id
       AND l_today BETWEEN ppf.effective_start_date AND ppf.effective_end_date
       AND paf.person_id = ppf.person_id
       AND paf.primary_flag = 'Y'
       AND paf.assignment_type = 'E'
       AND l_today BETWEEN paf.effective_start_date AND paf.effective_end_date
       AND hou.organization_id (+) = paf.organization_id
       AND pos.position_id (+) = paf.position_id
       AND l_today BETWEEN pos.effective_start_date (+) AND pos.effective_end_date (+)
       AND pj.job_id (+) = paf.job_id
       AND sup.person_id (+) = paf.supervisor_id
       AND l_today BETWEEN sup.effective_start_date (+) AND sup.effective_end_date (+);

    x_return_status := c_success;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      set_error(x_return_status, x_message,
                'User ' || p_user_name || ' is not linked to an active employee.');
    WHEN OTHERS THEN
      set_error(x_return_status, x_message, SQLERRM);
  END get_employee_profile;

  -- ---------------------------------------------------------------------------
  -- get_absence_types
  -- ---------------------------------------------------------------------------

  PROCEDURE get_absence_types (
    p_business_group_id IN  NUMBER,
    x_absence_types     OUT NOCOPY absence_type_tbl,
    x_return_status     OUT NOCOPY VARCHAR2,
    x_message           OUT NOCOPY VARCHAR2
  ) IS
    l_today DATE := TRUNC(SYSDATE);
  BEGIN
    SELECT paat.absence_attendance_type_id,
           paat.name,
           paat.absence_category
      BULK COLLECT INTO x_absence_types
      FROM per_absence_attendance_types paat
     WHERE paat.business_group_id = p_business_group_id
       AND l_today BETWEEN paat.date_effective AND NVL(paat.date_end, l_today)
     ORDER BY paat.name;

    x_return_status := c_success;
  EXCEPTION
    WHEN OTHERS THEN
      set_error(x_return_status, x_message, SQLERRM);
  END get_absence_types;

  -- ---------------------------------------------------------------------------
  -- get_vacation_balance
  -- ---------------------------------------------------------------------------

  PROCEDURE get_vacation_balance (
    p_person_id        IN  NUMBER,
    p_effective_date   IN  DATE     DEFAULT NULL,
    p_accrual_category IN  VARCHAR2 DEFAULT 'V',
    x_plan_name        OUT NOCOPY VARCHAR2,
    x_net_entitlement  OUT NOCOPY NUMBER,
    x_return_status    OUT NOCOPY VARCHAR2,
    x_message          OUT NOCOPY VARCHAR2
  ) IS
    l_date              DATE := TRUNC(NVL(p_effective_date, SYSDATE));
    l_assignment_id     NUMBER;
    l_payroll_id        NUMBER;
    l_business_group_id NUMBER;
    l_plan_id           NUMBER;
    l_start_date        DATE;
    l_end_date          DATE;
    l_accrual_end_date  DATE;
    l_accrual           NUMBER;
  BEGIN
    BEGIN
      get_primary_assignment(p_person_id, l_date, l_assignment_id, l_payroll_id, l_business_group_id);
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        set_error(x_return_status, x_message, 'No active primary assignment for this employee.');
        RETURN;
    END;

    -- Accrual plan the assignment is enrolled in, through its element entry.
    BEGIN
      SELECT pap.accrual_plan_id, pap.accrual_plan_name
        INTO l_plan_id, x_plan_name
        FROM pay_accrual_plans     pap,
             pay_element_links_f   pel,
             pay_element_entries_f pee
       WHERE pee.assignment_id = l_assignment_id
         AND l_date BETWEEN pee.effective_start_date AND pee.effective_end_date
         AND pel.element_link_id = pee.element_link_id
         AND l_date BETWEEN pel.effective_start_date AND pel.effective_end_date
         AND pap.accrual_plan_element_type_id = pel.element_type_id
         AND pap.accrual_category = p_accrual_category
         AND ROWNUM = 1;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        set_error(x_return_status, x_message, 'The employee is not enrolled in an accrual plan of this category.');
        RETURN;
    END;

    per_accrual_calc_functions.get_net_accrual (
      p_assignment_id          => l_assignment_id,
      p_plan_id                => l_plan_id,
      p_payroll_id             => l_payroll_id,
      p_business_group_id      => l_business_group_id,
      p_assignment_action_id   => -1,
      p_calculation_date       => l_date,
      p_accrual_start_date     => NULL,
      p_accrual_latest_balance => NULL,
      p_calling_point          => 'FRM',
      p_start_date             => l_start_date,
      p_end_date               => l_end_date,
      p_accrual_end_date       => l_accrual_end_date,
      p_accrual                => l_accrual,
      p_net_entitlement        => x_net_entitlement);

    x_return_status := c_success;
  EXCEPTION
    WHEN OTHERS THEN
      set_error(x_return_status, x_message, SQLERRM);
  END get_vacation_balance;

  -- ---------------------------------------------------------------------------
  -- get_employee_absences
  -- ---------------------------------------------------------------------------

  PROCEDURE get_employee_absences (
    p_person_id     IN  NUMBER,
    p_months_back   IN  NUMBER DEFAULT 12,
    x_absences      OUT NOCOPY absence_tbl,
    x_return_status OUT NOCOPY VARCHAR2,
    x_message       OUT NOCOPY VARCHAR2
  ) IS
  BEGIN
    SELECT paa.absence_attendance_id,
           paa.object_version_number,
           paa.person_id,
           ppf.full_name,
           paat.name,
           NVL(paa.date_start, paa.date_projected_start),
           NVL(paa.date_end, paa.date_projected_end),
           paa.absence_days,
           paa.comments,
           NVL(paa.attribute1, c_status_approved)
      BULK COLLECT INTO x_absences
      FROM per_absence_attendances      paa,
           per_absence_attendance_types paat,
           per_all_people_f             ppf
     WHERE paa.person_id = p_person_id
       AND paat.absence_attendance_type_id = paa.absence_attendance_type_id
       AND ppf.person_id = paa.person_id
       AND TRUNC(SYSDATE) BETWEEN ppf.effective_start_date AND ppf.effective_end_date
       AND NVL(paa.date_start, paa.date_projected_start) >= ADD_MONTHS(TRUNC(SYSDATE), -NVL(p_months_back, 12))
     ORDER BY NVL(paa.date_start, paa.date_projected_start) DESC;

    x_return_status := c_success;
  EXCEPTION
    WHEN OTHERS THEN
      set_error(x_return_status, x_message, SQLERRM);
  END get_employee_absences;

  -- ---------------------------------------------------------------------------
  -- get_manager_worklist
  -- ---------------------------------------------------------------------------

  PROCEDURE get_manager_worklist (
    p_manager_person_id IN  NUMBER,
    x_absences          OUT NOCOPY absence_tbl,
    x_return_status     OUT NOCOPY VARCHAR2,
    x_message           OUT NOCOPY VARCHAR2
  ) IS
    l_today DATE := TRUNC(SYSDATE);
  BEGIN
    SELECT paa.absence_attendance_id,
           paa.object_version_number,
           paa.person_id,
           ppf.full_name,
           paat.name,
           NVL(paa.date_start, paa.date_projected_start),
           NVL(paa.date_end, paa.date_projected_end),
           paa.absence_days,
           paa.comments,
           paa.attribute1
      BULK COLLECT INTO x_absences
      FROM per_absence_attendances      paa,
           per_absence_attendance_types paat,
           per_all_people_f             ppf,
           per_all_assignments_f        paf
     WHERE paf.supervisor_id = p_manager_person_id
       AND paf.primary_flag = 'Y'
       AND paf.assignment_type = 'E'
       AND l_today BETWEEN paf.effective_start_date AND paf.effective_end_date
       AND ppf.person_id = paf.person_id
       AND l_today BETWEEN ppf.effective_start_date AND ppf.effective_end_date
       AND paa.person_id = paf.person_id
       AND paa.attribute1 = c_status_pending
       AND paat.absence_attendance_type_id = paa.absence_attendance_type_id
     ORDER BY NVL(paa.date_start, paa.date_projected_start);

    x_return_status := c_success;
  EXCEPTION
    WHEN OTHERS THEN
      set_error(x_return_status, x_message, SQLERRM);
  END get_manager_worklist;

  -- ---------------------------------------------------------------------------
  -- decide_absence
  -- ---------------------------------------------------------------------------

  PROCEDURE decide_absence (
    p_absence_attendance_id IN  NUMBER,
    p_object_version_number IN  NUMBER,
    p_manager_person_id     IN  NUMBER,
    p_action                IN  VARCHAR2,
    p_comments              IN  VARCHAR2 DEFAULT NULL,
    x_object_version_number OUT NOCOPY NUMBER,
    x_return_status         OUT NOCOPY VARCHAR2,
    x_message               OUT NOCOPY VARCHAR2
  ) IS
    l_today         DATE := TRUNC(SYSDATE);
    l_status        VARCHAR2(30);
    l_person_id     NUMBER;
    l_current       VARCHAR2(150);
    l_days          NUMBER;
    l_hours         NUMBER;
    l_comments      VARCHAR2(2000);
    l_is_supervisor NUMBER;
    l_ovn           NUMBER := p_object_version_number;
    -- API warnings, not used by the app
    l_dur_dys_less_warning      BOOLEAN;
    l_dur_hrs_less_warning      BOOLEAN;
    l_exceeds_pto_entit_warning BOOLEAN;
    l_exceeds_run_total_warning BOOLEAN;
    l_abs_overlap_warning       BOOLEAN;
    l_abs_day_after_warning     BOOLEAN;
    l_dur_overwritten_warning   BOOLEAN;
    l_del_element_entry_warning BOOLEAN;
  BEGIN
    l_status := CASE UPPER(p_action)
                  WHEN 'APPROVE' THEN c_status_approved
                  WHEN 'REJECT'  THEN c_status_rejected
                END;
    IF l_status IS NULL THEN
      set_error(x_return_status, x_message, 'Action must be APPROVE or REJECT.');
      RETURN;
    END IF;

    BEGIN
      SELECT paa.person_id, paa.attribute1, paa.absence_days, paa.absence_hours, paa.comments
        INTO l_person_id, l_current, l_days, l_hours, l_comments
        FROM per_absence_attendances paa
       WHERE paa.absence_attendance_id = p_absence_attendance_id;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        set_error(x_return_status, x_message, 'Vacation request not found.');
        RETURN;
    END;

    IF NVL(l_current, 'X') <> c_status_pending THEN
      set_error(x_return_status, x_message, 'This request is not pending any more.');
      RETURN;
    END IF;

    SELECT COUNT(*)
      INTO l_is_supervisor
      FROM per_all_assignments_f paf
     WHERE paf.person_id = l_person_id
       AND paf.supervisor_id = p_manager_person_id
       AND paf.primary_flag = 'Y'
       AND l_today BETWEEN paf.effective_start_date AND paf.effective_end_date;

    IF l_is_supervisor = 0 THEN
      set_error(x_return_status, x_message, 'Only the employee''s supervisor can approve or reject this request.');
      RETURN;
    END IF;

    IF p_comments IS NOT NULL THEN
      l_comments := SUBSTR(l_comments || CASE WHEN l_comments IS NOT NULL THEN CHR(10) END
                           || 'Manager: ' || p_comments, 1, 2000);
    END IF;

    hr_person_absence_api.update_person_absence (
      p_validate                  => FALSE,
      p_effective_date            => l_today,
      p_absence_attendance_id     => p_absence_attendance_id,
      p_comments                  => l_comments,
      p_attribute1                => l_status,
      p_absence_days              => l_days,
      p_absence_hours             => l_hours,
      p_object_version_number     => l_ovn,
      p_dur_dys_less_warning      => l_dur_dys_less_warning,
      p_dur_hrs_less_warning      => l_dur_hrs_less_warning,
      p_exceeds_pto_entit_warning => l_exceeds_pto_entit_warning,
      p_exceeds_run_total_warning => l_exceeds_run_total_warning,
      p_abs_overlap_warning       => l_abs_overlap_warning,
      p_abs_day_after_warning     => l_abs_day_after_warning,
      p_dur_overwritten_warning   => l_dur_overwritten_warning,
      p_del_element_entry_warning => l_del_element_entry_warning);

    COMMIT;
    x_object_version_number := l_ovn;
    x_return_status := c_success;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      set_error(x_return_status, x_message, SQLERRM);
  END decide_absence;

END xx_hcm_mobile_ws;
/
