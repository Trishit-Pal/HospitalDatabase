-- Create Database
-- create database ehias;
use ehias;

-- Create Department table
create table departments
(
departmentid int auto_increment primary key,
name varchar(50) not null
) ;

-- Creating table doctors
create table doctors
(
doctorid int not null auto_increment primary key,
name varchar (50),
specialization varchar (100),
role varchar (50),
departmentid int,
foreign key (departmentid) references departments(departmentid)
);

-- Create Patients table
create table patients
(
patientid int auto_increment primary key,
name varchar (50),
dateofbirth date,
gender varchar(2),
phone varchar(10),
check (gender in ('m', 'f', 'o'))
);

-- Create Appointment table
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

-- Create Prescription table
create table prescriptions
(
prescriptionid int auto_increment primary key,
appointmentid int,
medication varchar (50),
dosage varchar(50),
foreign key (appointmentid) references appointments(appointmentid)
);

-- Create Bills table
create table bills
(
billid int auto_increment primary key,
appointmentid int,
amount decimal(10,2),
paid tinyint(1),
billdate datetime default current_timestamp,
foreign key (appointmentid) references appointments(appointmentid)
);

-- Create Lab Reports table
create table labreports
(
reportid int auto_increment primary key,
appointmentid int,
amount decimal(10,2),
reportdata text,
createdate datetime default current_timestamp,
foreign key (appointmentid) references appointments(appointmentid)
);

-- Rename hospital_data_10000_rows
rename table  hospital_data_10000_rows to hospital_data;

-- Insertion  of data into database
select * from hospital_data;
select 'Departments.DepartmentID' from hospital_data;

select column_name from information_schema.columns
where table_schema ='ehias'
and table_name ='hospital_data' and column_name like 'Departments.%';

select concat('select',group_concat(concat('`',column_name,'`')), ' from hospital_data') from information_schema.columns
where table_schema ='ehias'
and table_name ='hospital_data' AND column_name like 'Departments.%';
insert into departments(departmentid,name)
select `Departments.DepartmentID`, `Departments.Name` from hospital_data where `Departments.DepartmentID` <> '';

select * from departments;

-- Inserting values into doctors table
select concat ('select', group_concat(concat('`', column_name,'`')), 'from hospital_data')
from information_schema.columns where
table_schema ='ehias' and table_name='hospital_data' and column_name like 'Doctors.%';

insert into doctors(DepartmentID, DoctorID,Name, Role, Specialization)
select `Doctors.DepartmentID`, `Doctors.DoctorID`, `Doctors.Name`, `Doctors.Role`,
`Doctors.Specialization` from hospital_data where `Doctors.DepartmentID` <> '';

select * from doctors;

-- Inserting values into patients table
select concat ('select', group_concat(concat('`', column_name,'`')), 'from hospital_data')
from information_schema.columns where
table_schema ='ehias' and table_name='hospital_data' and column_name like 'Patients.%';

insert into patients(PatientID,Name, DateOfBirth,Gender,Phone)
select `Patients.PatientID`, `Patients.Name`, str_to_date(`Patients.DateOfBirth`,'%d-%m-%Y'), `Patients.Gender`,
`Patients.Phone` from hospital_data where `Patients.PatientID` <> '';

select * from patients;

-- Inserting values into Appointments table
select concat ('select', group_concat(concat('`', column_name,'`')), 'from hospital_data')
from information_schema.columns where
table_schema ='ehias' and table_name='hospital_data' and column_name like 'Appointments.%';

insert into appointments(appointmentID,patientid, doctorid,appointmenttime, status)
select `Appointments.AppointmentID`, `Appointments.PatientID`, `Appointments.DoctorID`, 
str_to_date(`Appointments.AppointmentTime`, '%d-%m-%Y %H:%i' ), `Appointments.Status`
from hospital_data where `Appointments.AppointmentID` <> '';

select * from appointments;

-- Inserting values into Prescriptions table
select concat ('select', group_concat(concat('`', column_name,'`')), 'from hospital_data')
from information_schema.columns where
table_schema ='ehias' and table_name='hospital_data' and column_name like 'Prescriptions.%';

insert into prescriptions(prescriptionID,appointmentid, medication, dosage)
select `Prescriptions.PrescriptionID`, `Prescriptions.AppointmentID`, `Prescriptions.Medication`, `Prescriptions.Dosage`
from hospital_data where `Prescriptions.PrescriptionID` <> '';

select * from prescriptions;


-- Inserting values into Bils table
select concat ('select', group_concat(concat('`', column_name,'`')), 'from hospital_data')
from information_schema.columns where
table_schema ='ehias' and table_name='hospital_data' and column_name like 'Bills.%';

insert into bills(billID,appointmentid, amount, paid, billdate)
select `Bills.BillID`, `Bills.AppointmentID`, `Bills.Amount`, `Bills.Paid`, str_to_date(`Bills.BillDate`, '%d-%m-%Y %H:%i')
from hospital_data where `Bills.BillID` <> '';

select * from bills;


-- Inserting values into LabReports table
select concat ('select', group_concat(concat('`', column_name,'`')), 'from hospital_data')
from information_schema.columns where
table_schema ='ehias' and table_name='hospital_data' and column_name like 'LabReports.%';

insert into labreports(reportid,appointmentid, reportdata, createdate)
select `LabReports.ReportID`, `LabReports.AppointmentID`, `LabReports.ReportData`, str_to_date(`LabReports.CreatedAt`, '%d-%m-%Y %H:%i')
from hospital_data where `LabReports.ReportID` <> '';

select * from labreports;

-- Creating Triggers
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

--
delimiter $$
create procedure view_doctor_data(in input_username varchar(100), in input_password varchar(100))
begin
	declare doc_role varchar(100);
    declare doc_dept int;
    declare doc_id int;
    
-- check credentials of doctor
	select doctor_id into doc_id
    from doctor_credentials
    where user_name= input_username and password =  input_password;
    
-- Get role and department from doctors table
	select role, departmentid
    into doc_role, doc_dept
    from doctors where doctorid= doc_id;

-- Show appropirate patients data
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


-- Solve Billing Issue
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


