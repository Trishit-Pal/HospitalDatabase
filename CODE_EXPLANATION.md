# EHIAS Code Explanation

A detailed step-by-step walkthrough of every SQL query, trigger, view, and procedure in this hospital database project. This document covers the logic, joins, and how all components connect end-to-end.

---

## Table of Contents

1. [Database Schema Design](#1-database-schema-design)
2. [Data Normalization Process](#2-data-normalization-process)
3. [Triggers](#3-triggers)
4. [Stored Procedures](#4-stored-procedures)
5. [Views](#5-views)
6. [Analytical Queries](#6-analytical-queries)
7. [Join Patterns Used](#7-join-patterns-used)
8. [Key SQL Techniques](#8-key-sql-techniques)
9. [Interview Q&A](#9-interview-qa)

---

## 1. Database Schema Design

### The Hub-and-Spoke Model

The entire database is built around the `appointments` table as the central hub. Every clinical and financial event connects through an appointment.

```
                    departments
                         |
                         | 1:N (one department has many doctors)
                         v
    patients -----> appointments <----- doctors
        |               |                   
        |          _____|_____              
        |         |     |     |             
        |         v     v     v             
        |    bills  prescriptions  labreports
        |
        +-- (appointments links patients to doctors at a specific time)
```

### Table Relationships

| Parent Table | Child Table | Foreign Key | Relationship |
|---|---|---|---|
| departments | doctors | doctors.departmentid | 1:N |
| patients | appointments | appointments.patientid | 1:N |
| doctors | appointments | appointments.doctorid | 1:N |
| appointments | prescriptions | prescriptions.appointmentid | 1:0..1 |
| appointments | bills | bills.appointmentid | 1:0..1 |
| appointments | labreports | labreports.appointmentid | 1:0..1 |

### Why This Design Matters

1. **Single source of truth**: To find everything about a patient visit, you start at `appointments` and join outward
2. **No redundancy**: Patient info is stored once, doctor info is stored once
3. **Easy analytics**: Revenue, prescriptions, and lab data all trace back through the appointment

---

## 2. Data Normalization Process

### The Problem: Flat CSV

The source data was a single CSV with 30+ columns containing everything denormalized:

```
Departments.DepartmentID, Departments.Name, Doctors.DoctorID, Doctors.Name, 
Patients.PatientID, Patients.Name, Appointments.AppointmentID, ...
```

### The Solution: ETL into Normalized Tables

The script uses dynamic SQL with `information_schema` to extract columns by prefix.

**Step 1: Discover columns**
```sql
select column_name from information_schema.columns
where table_schema = 'ehias'
and table_name = 'hospital_data' 
and column_name like 'Departments.%';
```
This queries MySQL's metadata catalog to find all columns starting with `Departments.`.

**Step 2: Insert into normalized table**
```sql
insert into departments(departmentid, name)
select `Departments.DepartmentID`, `Departments.Name` 
from hospital_data 
where `Departments.DepartmentID` <> '';
```

**Key technique**: The `where ... <> ''` clause filters out rows where that entity doesn't exist (since the flat CSV repeats values across rows).

**Date conversion with STR_TO_DATE**:
```sql
str_to_date(`Patients.DateOfBirth`, '%d-%m-%Y')
```
Converts string dates from DD-MM-YYYY format into proper MySQL DATE type.

```sql
str_to_date(`Appointments.AppointmentTime`, '%d-%m-%Y %H:%i')
```
Converts datetime strings with time component.

---

## 3. Triggers

Triggers are database-level event handlers that fire automatically on INSERT, UPDATE, or DELETE operations.

### 3.1 check_new_appointment (BEFORE INSERT)

**Purpose**: Prevent invalid appointment creation

**Logic**:
```sql
create trigger check_new_appointment
before insert on appointments for each row
begin 
    -- Rule 1: No past appointments
    if new.appointmenttime < NOW() then
        signal sqlstate '45000' 
        set message_text = 'Error: Appointment cannot be in the past';
    end if;
    
    -- Rule 2: No double-booking
    if exists (
        select * from appointments
        where doctorid = new.doctorid 
        and appointmenttime = new.appointmenttime
        and status in ('scheduled')
    ) then
        signal sqlstate '45000'
        set message_text = 'Error: Doctor already has an appointment at this time.';
    end if;
end
```

**How it works**:
1. `BEFORE INSERT` means this runs before the row is actually inserted
2. `NEW.column` refers to the values being inserted
3. `SIGNAL SQLSTATE '45000'` raises a user-defined error that aborts the insert
4. The `EXISTS` subquery checks if a conflicting appointment already exists

**Interview insight**: This is called a "defensive trigger" because it prevents bad data from ever entering the database.

### 3.2 check_appointment_update (BEFORE UPDATE)

**Purpose**: Same validation but for rescheduling

**Key difference from insert trigger**:
```sql
where appointmentid != new.appointmentid  -- exclude the row being updated
```
When checking for double-booking on UPDATE, we must exclude the current row itself.

### 3.3 prevent_doctor_delete (BEFORE DELETE)

**Purpose**: Protect referential integrity beyond foreign keys

```sql
create trigger prevent_doctor_delete
before delete on doctors for each row
begin
    if exists (
        select 1 from appointments
        where doctorid = old.doctorid
        and status = 'Scheduled'
        and appointmenttime > NOW()
    ) then
        signal sqlstate '45000'
        set message_text = 'Error: Cannot delete doctor with upcoming scheduled appointments.';
    end if;
end
```

**How it works**:
1. `OLD.doctorid` refers to the row being deleted
2. Only blocks if there are FUTURE scheduled appointments
3. Past or completed appointments don't block deletion

**Why not just use ON DELETE RESTRICT?** Foreign key constraints would block deletion if ANY appointments exist. This trigger allows deletion of doctors with only historical data.

### 3.4 validate_patient_phone (INSERT + UPDATE)

**Purpose**: Data quality enforcement

```sql
if length(new.phone) != 10 or new.phone regexp '[^0-9]' then
    signal sqlstate '45000'
    set message_text = 'Error: Phone number must be exactly 10 digits.';
end if;
```

**How it works**:
1. `LENGTH(new.phone) != 10` checks exact character count
2. `new.phone REGEXP '[^0-9]'` checks for non-digit characters
3. `[^0-9]` is a regex pattern meaning "any character that is NOT 0-9"

**Interview insight**: Two separate triggers (insert and update) are needed because MySQL doesn't support `BEFORE INSERT OR UPDATE` syntax.

### 3.5 auto_bill_on_completion (AFTER UPDATE)

**Purpose**: Automatic billing when appointment completes

```sql
create trigger auto_bill_on_completion
after update on appointments for each row
begin
    if old.status != 'Completed' and new.status = 'Completed' then
        if not exists (select 1 from bills where appointmentid = new.appointmentid) then
            insert into bills (appointmentid, amount, paid, billdate)
            values (new.appointmentid, round(500 + (rand() * 4500), 2), 0, NOW());
        end if;
    end if;
end
```

**How it works**:
1. `AFTER UPDATE` means the appointment row is already updated when this runs
2. `old.status != 'Completed' and new.status = 'Completed'` detects the status transition
3. The nested `NOT EXISTS` prevents duplicate bills
4. `ROUND(500 + (RAND() * 4500), 2)` generates a random amount between 500 and 5000

**Why AFTER not BEFORE?** We need the appointment update to succeed first. If we did BEFORE and the update failed, we'd have created a bill for a non-existent state.

---

## 4. Stored Procedures

Stored procedures encapsulate complex logic into reusable, parameterized routines.

### 4.1 view_doctor_data (Role-Based Access Control)

**Purpose**: Return patient data filtered by doctor's role level

**Full logic breakdown**:

```sql
create procedure view_doctor_data(in input_username varchar(100), in input_password varchar(100))
begin
    declare doc_role varchar(100);
    declare doc_dept int;
    declare doc_id int;
    
    -- Step 1: Authenticate - get doctor_id from credentials table
    select doctor_id into doc_id
    from doctor_credentials
    where user_name = input_username and password = input_password;
    
    -- Step 2: Get role and department from doctors table
    select role, departmentid
    into doc_role, doc_dept
    from doctors where doctorid = doc_id;

    -- Step 3: Return data based on role
    if doc_role = 'senior' then
        -- Seniors see ALL patients in their department
        select d.doctorid, p.patientid, p.name, p.gender, 
            a.appointmenttime, pr.medication, lr.reportdata 
        from patients p 
            inner join appointments a on a.patientid = p.patientid
            join doctors d on d.doctorid = a.doctorid
            left join prescriptions pr on a.appointmentid = pr.appointmentid
            left join labreports lr on a.appointmentid = lr.appointmentid 
        where d.departmentid = doc_dept;  -- filter by department
    else
        -- Others see ONLY their own patients
        select a.doctorid, p.patientid, p.name, p.gender, 
            a.appointmenttime, pr.medication, lr.reportdata 
        from patients p 
            inner join appointments a on a.patientid = p.patientid
            left join prescriptions pr on a.appointmentid = pr.appointmentid
            left join labreports lr on a.appointmentid = lr.appointmentid 
        where a.doctorid = doc_id;  -- filter by specific doctor
    end if;
end
```

**Key SQL concepts used**:
- `SELECT ... INTO variable` stores query result in a local variable
- `DECLARE` creates local procedure variables
- `IF-ELSE` branching based on role
- `LEFT JOIN` ensures patients appear even if they have no prescription/lab

**The join chain**:
```
patients -> appointments -> doctors -> prescriptions (optional)
                        |
                        +-> labreports (optional)
```

### 4.2 sp_monthlyrevenue (Revenue Aggregation)

**Purpose**: Department-wise revenue for a given month

```sql
create procedure sp_monthlyrevenue(in p_year int, p_month int)
begin
    select d1.name as department,
        sum(b.amount) as total_revenue 
    from bills b
        inner join appointments a on a.appointmentid = b.appointmentid
        inner join doctors d on a.doctorid = d.doctorid
        inner join departments d1 on d1.departmentid = d.departmentid 
    where month(b.billdate) = p_month and year(b.billdate) = p_year
    group by d1.name;
end
```

**The join chain explained**:
```
bills -> appointments -> doctors -> departments
(money)   (the visit)   (who saw)  (which unit)
```

To know which department earned revenue, we must trace:
1. Each bill belongs to an appointment
2. Each appointment was handled by a doctor
3. Each doctor belongs to a department

**Date filtering**:
- `MONTH(b.billdate) = p_month` extracts month component
- `YEAR(b.billdate) = p_year` extracts year component

### 4.3 sp_patient_history (Complete Patient Journey)

**Purpose**: One query to show everything about a patient's care history

```sql
select a.appointmentid, a.appointmenttime, a.status,
    d.name as doctor_name, d.specialization,
    pr.medication, pr.dosage,
    b.amount as bill_amount,
    case when b.paid = 1 then 'Paid' else 'Unpaid' end as payment_status,
    lr.reportdata as lab_results
from appointments a
    inner join doctors d on d.doctorid = a.doctorid
    left join prescriptions pr on pr.appointmentid = a.appointmentid
    left join bills b on b.appointmentid = a.appointmentid
    left join labreports lr on lr.appointmentid = a.appointmentid
where a.patientid = p_patientid
order by a.appointmenttime desc;
```

**Why LEFT JOINs?**
- Not every appointment results in a prescription (e.g., follow-up visits)
- Not every appointment has a lab report
- Bills might be missing for some appointments
- We want to see ALL appointments regardless of whether these optional records exist

**The CASE expression**:
```sql
case when b.paid = 1 then 'Paid' else 'Unpaid' end as payment_status
```
Converts the boolean `paid` column (0/1) into human-readable text.

### 4.4 sp_cancel_appointment (Validation Before Update)

**Purpose**: Safe appointment cancellation with business rule enforcement

```sql
create procedure sp_cancel_appointment(in p_appointmentid int)
begin
    declare current_status varchar(50);

    -- Get current status
    select status into current_status
    from appointments where appointmentid = p_appointmentid;

    -- Validate and act
    if current_status is null then
        signal sqlstate '45000'
        set message_text = 'Error: Appointment not found.';
    elseif current_status = 'Completed' then
        signal sqlstate '45000'
        set message_text = 'Error: Cannot cancel a completed appointment.';
    elseif current_status = 'Cancelled' then
        signal sqlstate '45000'
        set message_text = 'Error: Appointment is already cancelled.';
    else
        update appointments set status = 'Cancelled'
        where appointmentid = p_appointmentid;
        select 'Appointment cancelled successfully.' as result;
    end if;
end
```

**Why not just UPDATE directly?**
- Business rule: completed appointments cannot be cancelled (services were rendered)
- Business rule: already cancelled appointments shouldn't be re-cancelled
- UX: return meaningful error messages instead of silent failures

### 4.5 sp_abnormal_lab_reports (JSON Parsing)

**Purpose**: Flag patients with out-of-range lab values

**The JSON data structure in `reportdata`**:
```json
{"WBC": "4204", "RBC": "5.5", "Hemoglobin": "13.3"}
```

**Extracting values**:
```sql
json_extract(lr.reportdata, '$.WBC') as wbc
```
- `$.WBC` is a JSON path expression
- Returns the value with quotes: `"4204"`

**Converting for comparison**:
```sql
cast(json_unquote(json_extract(lr.reportdata, '$.WBC')) as unsigned)
```
1. `json_extract()` gets `"4204"` (with quotes)
2. `json_unquote()` removes quotes: `4204`
3. `cast(... as unsigned)` converts string to integer

**The flagging logic**:
```sql
case
    when cast(json_unquote(json_extract(lr.reportdata, '$.WBC')) as unsigned) < 4000
        then 'Low WBC'
    when cast(json_unquote(json_extract(lr.reportdata, '$.WBC')) as unsigned) > 11000
        then 'High WBC'
    when cast(json_unquote(json_extract(lr.reportdata, '$.Hemoglobin')) as decimal(4,1)) < 12.0
        then 'Low Hemoglobin'
    when cast(json_unquote(json_extract(lr.reportdata, '$.RBC')) as decimal(3,1)) < 4.0
        then 'Low RBC'
    else 'Review Needed'
end as flag_reason
```

**Clinical thresholds used**:
- WBC: 4000-11000 is normal range
- Hemoglobin: >= 12.0 g/dL is normal
- RBC: >= 4.0 million/mcL is normal

---

## 5. Views

Views are saved queries that act like virtual tables. They simplify complex joins for daily use.

### 5.1 vw_unpaid_bills

**Purpose**: One-stop query for the billing team

```sql
create view vw_unpaid_bills as
select b.billid, p.name as patient_name, p.phone,
    d.name as doctor_name, dep.name as department,
    b.amount, b.billdate
from bills b
    inner join appointments a on a.appointmentid = b.appointmentid
    inner join patients p on p.patientid = a.patientid
    inner join doctors d on d.doctorid = a.doctorid
    inner join departments dep on dep.departmentid = d.departmentid
where b.paid = 0;
```

**Usage**:
```sql
select * from vw_unpaid_bills where department = 'Cardiology';
select * from vw_unpaid_bills where billdate < DATE_SUB(NOW(), INTERVAL 30 DAY);
```

**Why a view instead of a procedure?**
- Views can be queried with WHERE, ORDER BY, LIMIT
- Views can be joined to other tables
- Procedures return result sets but can't be further filtered in SQL

### 5.2 vw_doctor_workload

**Purpose**: Appointment counts split by status per doctor

```sql
create view vw_doctor_workload as
select d.doctorid, d.name as doctor_name, d.specialization, d.role,
    dep.name as department,
    count(a.appointmentid) as total_appointments,
    sum(case when a.status = 'Completed' then 1 else 0 end) as completed,
    sum(case when a.status = 'Scheduled' then 1 else 0 end) as scheduled,
    sum(case when a.status = 'Cancelled' then 1 else 0 end) as cancelled
from doctors d
    inner join departments dep on dep.departmentid = d.departmentid
    left join appointments a on a.doctorid = d.doctorid
group by d.doctorid, d.name, d.specialization, d.role, dep.name;
```

**The conditional counting pattern**:
```sql
sum(case when a.status = 'Completed' then 1 else 0 end)
```
This is a pivot technique: for each row, add 1 if condition is true, else 0. The sum gives the count.

**Why LEFT JOIN to appointments?**
Doctors with zero appointments should still appear in the results with counts of 0.

### 5.3 vw_patient_profile

**Purpose**: Patient demographics with calculated fields

```sql
create view vw_patient_profile as
select p.patientid, p.name, p.dateofbirth,
    timestampdiff(year, p.dateofbirth, curdate()) as age,
    p.gender, p.phone,
    count(a.appointmentid) as total_visits,
    max(a.appointmenttime) as last_visit,
    sum(case when b.paid = 0 then b.amount else 0 end) as outstanding_balance
from patients p
    left join appointments a on a.patientid = p.patientid
    left join bills b on b.appointmentid = a.appointmentid
group by p.patientid, p.name, p.dateofbirth, p.gender, p.phone;
```

**Key techniques**:
- `TIMESTAMPDIFF(YEAR, dob, CURDATE())` calculates age in years
- `MAX(a.appointmenttime)` finds most recent visit
- Outstanding balance aggregates unpaid bill amounts

### 5.4 vw_department_dashboard

**Purpose**: Department-level KPIs

```sql
create view vw_department_dashboard as
select dep.departmentid, dep.name as department,
    count(distinct d.doctorid) as doctor_count,
    count(distinct a.appointmentid) as total_appointments,
    sum(case when a.status = 'Completed' then 1 else 0 end) as completed_appointments,
    round(sum(case when a.status = 'Completed' then 1 else 0 end) * 100.0
        / nullif(count(a.appointmentid), 0), 1) as completion_rate_pct,
    round(sum(case when a.status = 'Cancelled' then 1 else 0 end) * 100.0
        / nullif(count(a.appointmentid), 0), 1) as cancellation_rate_pct,
    coalesce(sum(b.amount), 0) as total_revenue,
    coalesce(sum(case when b.paid = 1 then b.amount else 0 end), 0) as collected_revenue,
    coalesce(sum(case when b.paid = 0 then b.amount else 0 end), 0) as pending_revenue
from departments dep
    left join doctors d on d.departmentid = dep.departmentid
    left join appointments a on a.doctorid = d.doctorid
    left join bills b on b.appointmentid = a.appointmentid
group by dep.departmentid, dep.name;
```

**The percentage calculation**:
```sql
round(sum(...) * 100.0 / nullif(count(...), 0), 1)
```
- `* 100.0` converts to percentage
- `NULLIF(x, 0)` returns NULL if x is 0, preventing division by zero
- `ROUND(..., 1)` rounds to 1 decimal place

**Why COUNT(DISTINCT)?**
Without DISTINCT, the count would be inflated because each bill row causes the doctor/appointment to be counted multiple times in the join result.

---

## 6. Analytical Queries

### 6.1 Top 10 Busiest Doctors

```sql
select d.doctorid, d.name, d.specialization, d.role,
    dep.name as department,
    count(a.appointmentid) as completed_appointments
from doctors d
    inner join departments dep on dep.departmentid = d.departmentid
    inner join appointments a on a.doctorid = d.doctorid
where a.status = 'Completed'
group by d.doctorid, d.name, d.specialization, d.role, dep.name
order by completed_appointments desc
limit 10;
```

**Key elements**:
- `WHERE a.status = 'Completed'` filters before aggregation (more efficient than HAVING)
- `GROUP BY` includes all non-aggregated columns
- `ORDER BY ... DESC LIMIT 10` is the top-N pattern

### 6.2 Most Prescribed Medications

```sql
select pr.medication,
    count(*) as times_prescribed,
    count(distinct a.doctorid) as prescribed_by_doctors,
    count(distinct a.patientid) as given_to_patients
from prescriptions pr
    inner join appointments a on a.appointmentid = pr.appointmentid
group by pr.medication
order by times_prescribed desc;
```

**Multi-dimensional counting**:
- `count(*)` = total prescriptions
- `count(distinct a.doctorid)` = unique doctors who prescribed this
- `count(distinct a.patientid)` = unique patients who received this

### 6.3 Patient Age Distribution

```sql
select
    case
        when timestampdiff(year, dateofbirth, curdate()) < 18 then 'Under 18'
        when timestampdiff(year, dateofbirth, curdate()) between 18 and 30 then '18-30'
        when timestampdiff(year, dateofbirth, curdate()) between 31 and 45 then '31-45'
        when timestampdiff(year, dateofbirth, curdate()) between 46 and 60 then '46-60'
        else 'Above 60'
    end as age_group,
    count(*) as patient_count,
    sum(case when gender = 'M' then 1 else 0 end) as male,
    sum(case when gender = 'F' then 1 else 0 end) as female,
    sum(case when gender = 'O' then 1 else 0 end) as other
from patients
group by age_group
order by field(age_group, 'Under 18', '18-30', '31-45', '46-60', 'Above 60');
```

**Bucketing with CASE**:
The CASE expression creates age brackets from continuous age values.

**Custom ordering with FIELD()**:
```sql
order by field(age_group, 'Under 18', '18-30', '31-45', '46-60', 'Above 60')
```
`FIELD(val, a, b, c)` returns the position of val in the list. This enables non-alphabetical ordering.

### 6.4 Doctors with Highest Cancellation Rates

```sql
select d.doctorid, d.name, d.specialization,
    count(*) as total_appointments,
    sum(case when a.status = 'Cancelled' then 1 else 0 end) as cancellations,
    round(sum(case when a.status = 'Cancelled' then 1 else 0 end) * 100.0
        / count(*), 1) as cancellation_pct
from doctors d
    inner join appointments a on a.doctorid = d.doctorid
group by d.doctorid, d.name, d.specialization
having count(*) >= 5
order by cancellation_pct desc
limit 10;
```

**HAVING vs WHERE**:
- `WHERE` filters rows BEFORE grouping
- `HAVING` filters groups AFTER aggregation
- `having count(*) >= 5` excludes doctors with too few appointments (statistically unreliable)

### 6.5 Monthly Trends

```sql
select year(appointmenttime) as yr, month(appointmenttime) as mn,
    count(*) as total_appointments,
    sum(case when status = 'Completed' then 1 else 0 end) as completed,
    sum(case when status = 'Cancelled' then 1 else 0 end) as cancelled
from appointments
group by year(appointmenttime), month(appointmenttime)
order by yr, mn;
```

**Time-series aggregation**:
- `YEAR()` and `MONTH()` extract date components
- Grouping by both creates monthly buckets
- Ordering by yr, mn gives chronological sequence

---

## 7. Join Patterns Used

### Pattern 1: Inner Join Chain (Revenue Tracing)
```
bills -> appointments -> doctors -> departments
```
Used when you need data from multiple tables and every link must exist.

### Pattern 2: Left Join for Optional Data
```
appointments -LEFT-> prescriptions
             -LEFT-> bills
             -LEFT-> labreports
```
Used when the left table rows should appear even without matching right table rows.

### Pattern 3: Hub Join (Everything Through Appointments)
```
patients -INNER-> appointments <-INNER- doctors
              |
              +-LEFT-> prescriptions
              +-LEFT-> bills
              +-LEFT-> labreports
```
The standard pattern for most queries in this database.

---

## 8. Key SQL Techniques

### Conditional Aggregation
```sql
sum(case when status = 'Completed' then 1 else 0 end)
```
Count rows matching a condition without multiple queries.

### Safe Division
```sql
nullif(count(*), 0)
```
Returns NULL instead of causing division-by-zero error.

### Date Bucketing
```sql
year(date_col), month(date_col)
```
Group data by time periods.

### Age Calculation
```sql
timestampdiff(year, dateofbirth, curdate())
```
Calculate years between two dates.

### JSON Operations
```sql
json_extract(column, '$.key')
json_unquote(...)
cast(... as unsigned)
```
Parse JSON stored in TEXT columns.

### Top-N Query
```sql
order by column desc limit N
```
Get highest/lowest N records.

### String Pattern Matching
```sql
where name like concat('%', search_term, '%')
```
Search with wildcards.

### REGEXP Validation
```sql
phone regexp '[^0-9]'
```
Check if string contains non-digit characters.

---

## 9. Interview Q&A

### Q: How would you find all patients who visited more than once?
```sql
select patientid, count(*) as visits
from appointments
group by patientid
having count(*) > 1;
```

### Q: How would you find the average revenue per department?
```sql
select dep.name, avg(b.amount) as avg_revenue
from bills b
    join appointments a on a.appointmentid = b.appointmentid
    join doctors d on d.doctorid = a.doctorid
    join departments dep on dep.departmentid = d.departmentid
group by dep.name;
```

### Q: How would you find patients who never paid any bill?
```sql
select distinct p.patientid, p.name
from patients p
    join appointments a on a.patientid = p.patientid
    join bills b on b.appointmentid = a.appointmentid
where b.paid = 0
and p.patientid not in (
    select a2.patientid
    from appointments a2
        join bills b2 on b2.appointmentid = a2.appointmentid
    where b2.paid = 1
);
```

### Q: How would you find the busiest day of the week?
```sql
select dayname(appointmenttime) as day_of_week,
    count(*) as appointments
from appointments
group by dayname(appointmenttime)
order by appointments desc;
```

### Q: How would you find doctors who have never had a cancellation?
```sql
select d.doctorid, d.name
from doctors d
where d.doctorid not in (
    select doctorid from appointments where status = 'Cancelled'
);
```

### Q: What's the difference between WHERE and HAVING?
- `WHERE` filters rows before grouping/aggregation
- `HAVING` filters groups after aggregation
- You can't use aggregate functions in WHERE

### Q: Why use LEFT JOIN instead of INNER JOIN?
LEFT JOIN keeps all rows from the left table even when there's no match on the right. Use it when the right table data is optional.

### Q: What is a trigger and when would you use one?
A trigger is code that runs automatically on INSERT/UPDATE/DELETE. Use it for:
- Data validation (phone format)
- Automatic record creation (auto-billing)
- Preventing invalid operations (double-booking)
- Maintaining referential integrity beyond foreign keys

### Q: What is the purpose of COALESCE?
`COALESCE(a, b)` returns the first non-NULL value. Used to replace NULL with a default:
```sql
coalesce(sum(amount), 0)  -- returns 0 instead of NULL when no rows
```

### Q: Explain the difference between COUNT(*) and COUNT(column)
- `COUNT(*)` counts all rows including those with NULL values
- `COUNT(column)` counts only rows where that column is not NULL
- `COUNT(DISTINCT column)` counts unique non-NULL values

---

This document covers the complete SQL codebase for the EHIAS hospital database. Each query is designed to solve a specific business problem while demonstrating important SQL concepts commonly tested in data analytics interviews.
