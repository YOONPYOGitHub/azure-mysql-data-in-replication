# mysqlbinlog 디코딩 샘플 — binlog_row_image = MINIMAL
# (binlog_tracking.md §3.4 참조용 / sanitize 됨: server-id·GTID UUID·DB명은 placeholder)
# FULL 샘플과 동일한 INSERT→UPDATE→DELETE 시퀀스를 MINIMAL 로 디코딩한 결과.
# UPDATE 는 WHERE 에 PK(@1)만, SET 에 변경된 컬럼(@2)만 / DELETE 는 WHERE 에 PK(@1)만 남는 점이 핵심.
/*!50530 SET @@SESSION.PSEUDO_SLAVE_MODE=1*/;
/*!50003 SET @OLD_COMPLETION_TYPE=@@COMPLETION_TYPE,COMPLETION_TYPE=0*/;
DELIMITER /*!*/;
#260605 15:11:14 server id <server-id>  end_log_pos 4720426 	GTID	last_committed=11935	sequence_number=11937	rbr_only=yes
/*!50718 SET TRANSACTION ISOLATION LEVEL READ COMMITTED*//*!*/;
SET @@SESSION.GTID_NEXT= '<source-uuid>:19652'/*!*/;
#260605 15:11:14 server id <server-id>  end_log_pos 4720506 	Query	thread_id=35	exec_time=0	error_code=0
SET TIMESTAMP=1780672274/*!*/;
BEGIN
/*!*/;
#260605 15:11:14 server id <server-id>  end_log_pos 4720580 	Table_map: `<db>`.`rowimg_demo` mapped to number 125
# has_generated_invisible_primary_key=0
#260605 15:11:14 server id <server-id>  end_log_pos 4720642 	Write_rows: table id 125 flags: STMT_END_F
### INSERT INTO `<db>`.`rowimg_demo`
### SET
###   @1=2 /* INT meta=0 nullable=0 is_null=0 */
###   @2='a_init_2' /* VARSTRING(200) meta=200 nullable=1 is_null=0 */
###   @3='b_init_2' /* VARSTRING(200) meta=200 nullable=1 is_null=0 */
###   @4=20 /* INT meta=0 nullable=1 is_null=0 */
#260605 15:11:14 server id <server-id>  end_log_pos 4720716 	Table_map: `<db>`.`rowimg_demo` mapped to number 125
# has_generated_invisible_primary_key=0
#260605 15:11:14 server id <server-id>  end_log_pos 4720770 	Update_rows: table id 125 flags: STMT_END_F
### UPDATE `<db>`.`rowimg_demo`
### WHERE
###   @1=2 /* INT meta=0 nullable=0 is_null=0 */
### SET
###   @2='a_UPDATED_2' /* VARSTRING(200) meta=200 nullable=1 is_null=0 */
#260605 15:11:14 server id <server-id>  end_log_pos 4720844 	Table_map: `<db>`.`rowimg_demo` mapped to number 125
# has_generated_invisible_primary_key=0
#260605 15:11:14 server id <server-id>  end_log_pos 4720884 	Delete_rows: table id 125 flags: STMT_END_F
### DELETE FROM `<db>`.`rowimg_demo`
### WHERE
###   @1=2 /* INT meta=0 nullable=0 is_null=0 */
#260605 15:11:14 server id <server-id>  end_log_pos 4720915 	Xid = 437921
COMMIT/*!*/;
SET @@SESSION.GTID_NEXT= 'AUTOMATIC' /* added by mysqlbinlog */ /*!*/;
DELIMITER ;
# End of log file
/*!50003 SET COMPLETION_TYPE=@OLD_COMPLETION_TYPE*/;
/*!50530 SET @@SESSION.PSEUDO_SLAVE_MODE=0*/;
