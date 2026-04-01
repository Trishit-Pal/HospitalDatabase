use ehias;

-- Table definitions

create table departments
(
departmentid int auto_increment primary key,
name varchar(50) not null
) ;

create table doctors
(
doctorid int not null auto_increment primary key,
name varchar (50),
specialization varchar (100),
role varchar (50),
departmentid int,
foreign key (departmentid) references departments(departmentid)
);

create table patients
(
patientid int auto_increment primary key,
name varchar (50),
dateofbirth date,
gender varchar(2),
phone varchar(10),
check (gender in ('m', 'f', 'o'))
);

create table appointments
(
appointmentid int auto_increment primary key,
patientid int,
doctorid int,
appointmenttime datetime,
status varchar(50),
foreign key (patientid) references patients(patientid),
foreign key (doctorid) references doctors(doctorid),
check (status in ('Scheduled','Completed','Cancelled'))
);

create table prescriptions
(
prescriptionid int auto_increment primary key,
appointmentid int,
medication varchar (50),
dosage varchar(50),
foreign key (appointmentid) references appointments(appointmentid)
);

create table bills
(
billid int auto_increment primary key,
appointmentid int,
amount decimal(10,2),
paid tinyint(1),
billdate datetime default current_timestamp,
foreign key (appointmentid) references appointments(appointmentid)
);

create table labreports
(
reportid int auto_increment primary key,
appointmentid int,
amount decimal(10,2),
reportdata text,
createdate datetime default current_timestamp,
foreign key (appointmentid) references appointments(appointmentid)
);

-- Data import from flat CSV into normalized tables

rename table  hospital_data_10000_rows to hospital_data;

select * from hospital_data;
select 'Departments.DepartmentID' from hospital_data;

select column_name from information_schema.columns
where table_schema ='ehias'
and table_name ='hospital_data' and column_name like 'Departments.%';

select concat('select',group_concat(concat('`',column_name,'`')), ' from hospital_data') from information_schema.columns
where table_schema ='ehias'
and table_name ='hospital_data' AND column_name like 'Departments.%';

-- departments
insert into departments(departmentid,name)
select `Departments.DepartmentID`, `Departments.Name` from hospital_data where `Departments.DepartmentID` <> '';

select * from departments;

-- doctors
select concat ('select', group_concat(concat('`', column_name,'`')), 'from hospital_data')
from information_schema.columns where
table_schema ='ehias' and table_name='hospital_data' and column_name like 'Doctors.%';

insert into doctors(DepartmentID, DoctorID,Name, Role, Specialization)
select `Doctors.DepartmentID`, `Doctors.DoctorID`, `Doctors.Name`, `Doctors.Role`,
`Doctors.Specialization` from hospital_data where `Doctors.DepartmentID` <> '';

select * from doctors;

-- patients
select concat ('select', group_concat(concat('`', column_name,'`')), 'from hospital_data')
from information_schema.columns where
table_schema ='ehias' and table_name='hospital_data' and column_name like 'Patients.%';

insert into patients(PatientID,Name, DateOfBirth,Gender,Phone)
select `Patients.PatientID`, `Patients.Name`, str_to_date(`Patients.DateOfBirth`,'%d-%m-%Y'), `Patients.Gender`,
`Patients.Phone` from hospital_data where `Patients.PatientID` <> '';

select * from patients;

-- appointments
select concat ('select', group_concat(concat('`', column_name,'`')), 'from hospital_data')
from information_schema.columns where
table_schema ='ehias' and table_name='hospital_data' and column_name like 'Appointments.%';

insert into appointments(appointmentID,patientid, doctorid,appointmenttime, status)
select `Appointments.AppointmentID`, `Appointments.PatientID`, `Appointments.DoctorID`, 
str_to_date(`Appointments.AppointmentTime`, '%d-%m-%Y %H:%i' ), `Appointments.Status`
from hospital_data where `Appointments.AppointmentID` <> '';

select * from appointments;

-- prescriptions
select concat ('select', group_concat(concat('`', column_name,'`')), 'from hospital_data')
from information_schema.columns where
table_schema ='ehias' and table_name='hospital_data' and column_name like 'Prescriptions.%';

insert into prescriptions(prescriptionID,appointmentid, medication, dosage)
select `Prescriptions.PrescriptionID`, `Prescriptions.AppointmentID`, `Prescriptions.Medication`, `Prescriptions.Dosage`
from hospital_data where `Prescriptions.PrescriptionID` <> '';

select * from prescriptions;

-- bills
select concat ('select', group_concat(concat('`', column_name,'`')), 'from hospital_data')
from information_schema.columns where
table_schema ='ehias' and table_name='hospital_data' and column_name like 'Bills.%';

insert into bills(billID,appointmentid, amount, paid, billdate)
select `Bills.BillID`, `Bills.AppointmentID`, `Bills.Amount`, `Bills.Paid`, str_to_date(`Bills.BillDate`, '%d-%m-%Y %H:%i')
from hospital_data where `Bills.BillID` <> '';

select * from bills;

-- labreports
select concat ('select', group_concat(concat('`', column_name,'`')), 'from hospital_data')
from information_schema.columns where
table_schema ='ehias' and table_name='hospital_data' and column_name like 'LabReports.%';

insert into labreports(reportid,appointmentid, reportdata, createdate)
select `LabReports.ReportID`, `LabReports.AppointmentID`, `LabReports.ReportData`, str_to_date(`LabReports.CreatedAt`, '%d-%m-%Y %H:%i')
from hospital_data where `LabReports.ReportID` <> '';

select * from labreports;


-- Triggers

-- block past-time inserts and double-booking on new appointments
drop trigger check_new_appointment

delimiter $$
create trigger check_new_appointment
before  insert on appointments for each row
begin 
	if new.appointmenttime <NOW() then
		signal sqlstate '45000' 
		set message_text ='Error: Appointment cannot be in the past';
    end if;
    
	if exists
        (
		select * from appointments
		where doctorid= new.doctorid and 
		appointmenttime = new.appointmenttime
        and status in ('scheduled')
		)then
        signal sqlstate '45000'
        set message_text= 'Error: Doctor already has an appointment at this time.';
	end if;
end $$
delimiter ;

insert into appointments (appointmentid, patientid, doctorid, appointmenttime, status)
values (19098,1,1,'2026-03-29 20:00:00', 'Scheduled');

-- role-based patient data access after doctor login
delimiter $$
create procedure view_doctor_data(in input_username varchar(100), in input_password varchar(100))
begin
	declare doc_role varchar(100);
    declare doc_dept int;
    declare doc_id int;
    
	select doctor_id into doc_id
    from doctor_credentials
    where user_name= input_username and password =  input_password;
    
	select role, departmentid
    into doc_role, doc_dept
    from doctors where doctorid= doc_id;

	if doc_role='senior' then
		select d.doctorid, p.patientid, p.name as 'Patient Name', p.gender, 
		a.appointmenttime, pr.medication, lr.reportdata from patients as p inner join
		appointments as a on a.patientid=p.patientid
        join doctors d on d.doctorid=a.doctorid
        left join prescriptions as pr on a.appointmentid= pr.appointmentid
		left join labreports as lr on a.appointmentid=lr.appointmentid 
        where d.departmentid=doc_dept;
	else
		select a.doctorid, p.patientid, p.name as 'Patient Name', p.gender, 
		a.appointmenttime, pr.medication, lr.reportdata from patients as p inner join
		appointments as a on a.patientid=p.patientid
        left join prescriptions as pr on a.appointmentid= pr.appointmentid
		left join labreports as lr on a.appointmentid=lr.appointmentid 
        where a.doctorid=doc_id;
	end if;
    
end $$
delimiter ;

call view_doctor_data('doctor2', 'lBYqWawB')
call view_doctor_data('doctor4', 'ic0pFSn0')

-- department-wise monthly revenue
delimiter //
create procedure sp_monthlyrevenue (in P_year int, p_month int)
begin
select d1.name as department,
	sum(b.amount) as total_revenue from bills as b
	inner join appointments as a on a.appointmentid=b.appointmentid
	inner join doctors as d on a.doctorid= d.doctorid
	inner join departments as d1 on d1.departmentid = d.departmentid 
	where month(b.billdate)= p_month and year(b.billdate)=p_year
group by d1.name;
end//
delimiter ;

call sp_monthlyrevenue(2025,5)


-- block past-time reschedules and double-booking on updates
delimiter $$
create trigger check_appointment_update
before update on appointments for each row
begin
	if new.appointmenttime < NOW() and new.status = 'Scheduled' then
		signal sqlstate '45000'
		set message_text = 'Error: Cannot reschedule appointment to a past time.';
	end if;

	if new.status = 'Scheduled' and exists (
		select 1 from appointments
		where doctorid = new.doctorid
		and appointmenttime = new.appointmenttime
		and appointmentid != new.appointmentid
		and status = 'Scheduled'
	) then
		signal sqlstate '45000'
		set message_text = 'Error: Doctor already has an appointment at this time.';
	end if;
end $$
delimiter ;

-- block deletion of doctors with upcoming appointments
delimiter $$
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
end $$
delimiter ;

-- phone must be exactly 10 digits
delimiter $$
create trigger validate_patient_phone_insert
before insert on patients for each row
begin
	if length(new.phone) != 10 or new.phone regexp '[^0-9]' then
		signal sqlstate '45000'
		set message_text = 'Error: Phone number must be exactly 10 digits.';
	end if;
end $$
delimiter ;

delimiter $$
create trigger validate_patient_phone_update
before update on patients for each row
begin
	if length(new.phone) != 10 or new.phone regexp '[^0-9]' then
		signal sqlstate '45000'
		set message_text = 'Error: Phone number must be exactly 10 digits.';
	end if;
end $$
delimiter ;

-- auto-generate a bill when appointment is marked completed
delimiter $$
create trigger auto_bill_on_completion
after update on appointments for each row
begin
	if old.status != 'Completed' and new.status = 'Completed' then
		if not exists (select 1 from bills where appointmentid = new.appointmentid) then
			insert into bills (appointmentid, amount, paid, billdate)
			values (new.appointmentid, round(500 + (rand() * 4500), 2), 0, NOW());
		end if;
	end if;
end $$
delimiter ;


-- Views

-- all unpaid bills with patient and doctor details
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

select * from vw_unpaid_bills;

-- appointment counts per doctor split by status
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

select * from vw_doctor_workload order by total_appointments desc limit 20;

-- patient demographics with age, visit count, and balance
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

select * from vw_patient_profile order by total_visits desc limit 20;

-- department KPIs: completion rate, cancellation rate, revenue
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

select * from vw_department_dashboard order by total_revenue desc;

-- today's scheduled appointments for the front desk
create view vw_todays_appointments as
select a.appointmentid, p.name as patient_name, p.phone,
	d.name as doctor_name, d.specialization,
	dep.name as department, a.appointmenttime, a.status
from appointments a
	inner join patients p on p.patientid = a.patientid
	inner join doctors d on d.doctorid = a.doctorid
	inner join departments dep on dep.departmentid = d.departmentid
where date(a.appointmenttime) = curdate()
and a.status = 'Scheduled';

select * from vw_todays_appointments;


-- Stored procedures

-- search patients by name or phone
delimiter $$
create procedure sp_search_patient(in search_term varchar(50))
begin
	select patientid, name, dateofbirth, gender, phone
	from patients
	where name like concat('%', search_term, '%')
	or phone like concat('%', search_term, '%');
end $$
delimiter ;

call sp_search_patient('Patient 1');

-- full patient history: visits, prescriptions, labs, bills
delimiter $$
create procedure sp_patient_history(in p_patientid int)
begin
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
end $$
delimiter ;

call sp_patient_history(1);

-- doctor's appointment schedule for a date range
delimiter $$
create procedure sp_doctor_schedule(in p_doctorid int, in p_start date, in p_end date)
begin
	select a.appointmentid, a.appointmenttime, a.status,
		p.name as patient_name, p.phone, p.gender
	from appointments a
		inner join patients p on p.patientid = a.patientid
	where a.doctorid = p_doctorid
	and date(a.appointmenttime) between p_start and p_end
	order by a.appointmenttime;
end $$
delimiter ;

call sp_doctor_schedule(1, '2024-01-01', '2025-12-31');

-- cancel an appointment with status validation
delimiter $$
create procedure sp_cancel_appointment(in p_appointmentid int)
begin
	declare current_status varchar(50);

	select status into current_status
	from appointments where appointmentid = p_appointmentid;

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
end $$
delimiter ;

-- unpaid bills summary grouped by department
delimiter $$
create procedure sp_outstanding_bills()
begin
	select dep.name as department,
		count(b.billid) as unpaid_count,
		sum(b.amount) as total_outstanding,
		round(avg(b.amount), 2) as avg_bill_amount,
		min(b.billdate) as oldest_unpaid_date
	from bills b
		inner join appointments a on a.appointmentid = b.appointmentid
		inner join doctors d on d.doctorid = a.doctorid
		inner join departments dep on dep.departmentid = d.departmentid
	where b.paid = 0
	group by dep.name
	order by total_outstanding desc;
end $$
delimiter ;

call sp_outstanding_bills();

-- annual revenue by department with collection rate
delimiter $$
create procedure sp_yearly_revenue(in p_year int)
begin
	select dep.name as department,
		count(b.billid) as total_bills,
		sum(b.amount) as total_revenue,
		sum(case when b.paid = 1 then b.amount else 0 end) as collected,
		sum(case when b.paid = 0 then b.amount else 0 end) as pending,
		round(sum(case when b.paid = 1 then b.amount else 0 end) * 100.0
			/ nullif(sum(b.amount), 0), 1) as collection_rate_pct
	from bills b
		inner join appointments a on a.appointmentid = b.appointmentid
		inner join doctors d on d.doctorid = a.doctorid
		inner join departments dep on dep.departmentid = d.departmentid
	where year(b.billdate) = p_year
	group by dep.name
	order by total_revenue desc;
end $$
delimiter ;

call sp_yearly_revenue(2024);
call sp_yearly_revenue(2025);

-- flag lab reports with abnormal WBC, RBC, or hemoglobin values
delimiter $$
create procedure sp_abnormal_lab_reports()
begin
	select lr.reportid, p.name as patient_name, p.patientid,
		d.name as doctor_name,
		json_extract(lr.reportdata, '$.WBC') as wbc,
		json_extract(lr.reportdata, '$.RBC') as rbc,
		json_extract(lr.reportdata, '$.Hemoglobin') as hemoglobin,
		lr.createdate,
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
	from labreports lr
		inner join appointments a on a.appointmentid = lr.appointmentid
		inner join patients p on p.patientid = a.patientid
		inner join doctors d on d.doctorid = a.doctorid
	where cast(json_unquote(json_extract(lr.reportdata, '$.WBC')) as unsigned) < 4000
		or cast(json_unquote(json_extract(lr.reportdata, '$.WBC')) as unsigned) > 11000
		or cast(json_unquote(json_extract(lr.reportdata, '$.Hemoglobin')) as decimal(4,1)) < 12.0
		or cast(json_unquote(json_extract(lr.reportdata, '$.RBC')) as decimal(3,1)) < 4.0
	order by lr.createdate desc;
end $$
delimiter ;

call sp_abnormal_lab_reports();


-- Analytical queries

-- top 10 busiest doctors by completed appointments
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

-- most prescribed medications
select pr.medication,
	count(*) as times_prescribed,
	count(distinct a.doctorid) as prescribed_by_doctors,
	count(distinct a.patientid) as given_to_patients
from prescriptions pr
	inner join appointments a on a.appointmentid = pr.appointmentid
group by pr.medication
order by times_prescribed desc;

-- cancellation rate by specialization
select d.specialization,
	count(*) as total,
	sum(case when a.status = 'Completed' then 1 else 0 end) as completed,
	sum(case when a.status = 'Scheduled' then 1 else 0 end) as scheduled,
	sum(case when a.status = 'Cancelled' then 1 else 0 end) as cancelled,
	round(sum(case when a.status = 'Cancelled' then 1 else 0 end) * 100.0
		/ count(*), 1) as cancellation_pct
from appointments a
	inner join doctors d on d.doctorid = a.doctorid
group by d.specialization
order by total desc;

-- revenue by specialization
select d.specialization,
	count(b.billid) as bill_count,
	sum(b.amount) as total_revenue,
	round(avg(b.amount), 2) as avg_bill,
	max(b.amount) as highest_bill,
	min(b.amount) as lowest_bill
from bills b
	inner join appointments a on a.appointmentid = b.appointmentid
	inner join doctors d on d.doctorid = a.doctorid
group by d.specialization
order by total_revenue desc;

-- patient age group distribution with gender breakdown
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

-- monthly appointment trends
select year(appointmenttime) as yr, month(appointmenttime) as mn,
	count(*) as total_appointments,
	sum(case when status = 'Completed' then 1 else 0 end) as completed,
	sum(case when status = 'Cancelled' then 1 else 0 end) as cancelled
from appointments
group by year(appointmenttime), month(appointmenttime)
order by yr, mn;

-- patients with highest outstanding balance
select p.patientid, p.name, p.phone,
	count(b.billid) as unpaid_bills,
	sum(b.amount) as total_outstanding
from patients p
	inner join appointments a on a.patientid = p.patientid
	inner join bills b on b.appointmentid = a.appointmentid
where b.paid = 0
group by p.patientid, p.name, p.phone
order by total_outstanding desc
limit 15;

-- doctors with highest cancellation rates (min 5 appointments)
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

-- doctor role distribution per department
select dep.name as department,
	sum(case when d.role = 'Senior' then 1 else 0 end) as seniors,
	sum(case when d.role = 'Junior' then 1 else 0 end) as juniors,
	sum(case when d.role = 'Consultant' then 1 else 0 end) as consultants,
	sum(case when d.role = 'Resident' then 1 else 0 end) as residents,
	count(*) as total_doctors
from doctors d
	inner join departments dep on dep.departmentid = d.departmentid
group by dep.name
order by total_doctors desc;

-- average revenue per doctor by role
select d.role,
	count(distinct d.doctorid) as doctor_count,
	round(sum(b.amount) / count(distinct d.doctorid), 2) as avg_revenue_per_doctor,
	round(avg(b.amount), 2) as avg_bill_amount
from doctors d
	inner join appointments a on a.doctorid = d.doctorid
	inner join bills b on b.appointmentid = a.appointmentid
group by d.role
order by avg_revenue_per_doctor desc;

-- prescription patterns: medication by specialization
select d.specialization, pr.medication,
	count(*) as prescription_count
from prescriptions pr
	inner join appointments a on a.appointmentid = pr.appointmentid
	inner join doctors d on d.doctorid = a.doctorid
group by d.specialization, pr.medication
order by d.specialization, prescription_count desc;

-- repeat patients with more than 3 visits
select p.patientid, p.name, p.phone, p.gender,
	count(a.appointmentid) as visit_count,
	count(distinct a.doctorid) as doctors_seen,
	min(a.appointmenttime) as first_visit,
	max(a.appointmenttime) as latest_visit
from patients p
	inner join appointments a on a.patientid = p.patientid
group by p.patientid, p.name, p.phone, p.gender
having visit_count > 3
order by visit_count desc;

-- overall bill collection summary
select
	count(*) as total_bills,
	sum(case when paid = 1 then 1 else 0 end) as paid_count,
	sum(case when paid = 0 then 1 else 0 end) as unpaid_count,
	sum(amount) as total_billed,
	sum(case when paid = 1 then amount else 0 end) as total_collected,
	sum(case when paid = 0 then amount else 0 end) as total_pending,
	round(sum(case when paid = 1 then amount else 0 end) * 100.0
		/ sum(amount), 1) as collection_rate_pct
from bills;
