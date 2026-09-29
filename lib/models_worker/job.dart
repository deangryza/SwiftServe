class Job {
 final String id,service,clientName,location,dateTime,price,status;
 const Job({required this.id,required this.service,required this.clientName,required this.location,required this.dateTime,required this.price,required this.status});
 factory Job.fromJson(Map<String,dynamic> j)=>Job(id:j['id']??'',service:j['service']??'',clientName:j['clientName']??'',location:j['location']??'',dateTime:j['dateTime']??'',price:j['price']??'',status:j['status']??'');
}