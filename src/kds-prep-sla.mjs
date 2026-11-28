/** Kitchen prep SLA timer and one-shot escalation policy. */
export function evaluatePrepSla({ticketId,stationId,startedAt,targetMinutes,now,pausedSeconds=0,escalationAlreadyCreated=false}){
 if(!ticketId||!stationId||!Number.isInteger(targetMinutes)||targetMinutes<1||!Number.isFinite(Date.parse(startedAt))||!Number.isFinite(Date.parse(now))||!Number.isFinite(pausedSeconds)||pausedSeconds<0)throw new Error("KDS_SLA_INPUT_INVALID");
 const elapsed=Math.max(0,(Date.parse(now)-Date.parse(startedAt))/1000-pausedSeconds);
 const target=targetMinutes*60,overdue=elapsed>target;
 return Object.freeze({ticket_id:ticketId,station_id:stationId,elapsed_seconds:Math.floor(elapsed),target_seconds:target,overdue,escalate:overdue&&!escalationAlreadyCreated,escalation_idempotency_key:"kds-sla:"+ticketId+":"+stationId});
}
