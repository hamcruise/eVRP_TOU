using CP;
int OptVehCnt=...;
int OptDist=...;
//float OptCost=...;
int nv = OptVehCnt; // Number of Trucks
float QQ=...;
float gg=...;
int f=100;
int Q=ftoi(ceil(QQ*f)); //77.5; // Vehicle fuel tank capacity
int g=ftoi(ceil(gg*f));//  3.47; //inverse refueling rate
int C=...;  //Vehicle load capacity
int h=...;    //fuel consumption rate
int v=...; // average Velocity 


tuple t_Job {
key string sid; 
	string t;  // d: depot, f:charging station, c:customer
    float x;
 	float y;
    float q;
    float e;  
    float l;
    float s;    
  };
{t_Job} Jobs = ...;

tuple t_augJob {
	int id;
	string sid; 
	string t; // d: depot, f:charging station, c:customer
    int x;
 	int y;
    int q; // quantity
    int e; // earliest  
    int l; // latest
    int s; // service time   
  };
{t_augJob} aJobs;
execute {
var i=1;
for(var j in Jobs) {
    aJobs.add(i++,j.sid,j.t,j.x,j.y,j.q,j.e,j.l,j.s )
	if(j.t=="d") aJobs.add(i++,"DN",j.t,j.x,j.y,j.q,j.e,j.l,j.s );      //dummy depot
  	if(j.t=="f") for(var k=1; k<=1; k++) aJobs.add(i++,j.sid,j.t,j.x,j.y,j.q,j.e,j.l,j.s ); //dummy fuel
    }
};
{t_augJob} fJobs= {i | i in aJobs : i.t=="f"};


int d[i in aJobs][j in aJobs] = ftoi(round(sqrt((i.x-j.x)*(i.x-j.x)+(i.y-j.y)*(i.y-j.y))));
int t[i in aJobs][j in aJobs]= ftoi(round(d[i,j]/v)); //integer
int l0 = min(j in aJobs: j.t=="d") j.l;
int T = max(j in aJobs) j.l; // by Myoungju Park
range Times = 0..T-1;  
int p[0..71]=[26,26,27,26,26,29,36,46,44,39,53,47,42,42,40,39,48,67,78,80,81,73,63,48,
			  26,26,27,26,26,29,36,46,44,39,53,47,42,42,40,39,48,67,78,80,81,73,63,48,
			  26,26,27,26,26,29,36,46,44,39,53,47,42,42,40,39,48,67,78,80,81,73,63,48];
int ep[Times]; //minute by minute pricing
execute {
var i;
var k;
for(var t in Times){	
	i= Opl.floor(t/60);
	ep[t]=p[i];
}	 
//writeln("ep",ep);
}
stepFunction EnergyPrice = stepwise(t in Times) { ep[t]-> t*100; ep[0]}; 

tuple t_Pair {
	int id1;
	string sid1; 
	string t1; // d: depot, f:charging station, c:customer
    int x1;
 	int y1;
    int q1; // quantity
    int e1; // earliest  
    int l1; // latest
    int s1; // service time   
	int id2;    
	string sid2; 
	string t2; // d: depot, f:charging station, c:customer
    int x2;
 	int y2;
    int q2; // quantity
    int e2; // earliest  
    int l2; // latest
    int s2; // service time   
    int d;
  };
{t_Pair} pair;

execute {
for(var j1 in aJobs) for(var j2 in aJobs) {
	if(j1!=j2 
   	  && !(j1.t=="d" && j2.t=="d")// prevent depot to depot
   	  && !(j1.t=="f" && j2.t=="f")// prevent charge to charge 
	  && j1.q + j2.q <= C         // sum of quantity must be smaller
	  && d[j1][j2] <= Q           // distance must be smaller
	  && j1.e + d[j1][j2]  < j2.l // j1.e +d(1,2) < j2.l  
	//  && (j1.t=="c" && j2.t=="c" && j1.l + d[j1][j2]  >= j2.e)    
	  ) 
	  pair.add(j1.id,j1.sid,j1.t,j1.x,j1.y,j1.q,j1.e,j1.l,j1.s,j2.id,j2.sid,j2.t,j2.x,j2.y,j2.q,j2.e,j2.l,j2.s,
	   Opl.ftoi(Opl.round(Opl.sqrt( (j1.x-j2.x)*(j1.x-j2.x)+(j1.y-j2.y)*(j1.y-j2.y)))));
}
}
//New triples by Myoungju Park
tuple t_Triple {
	string sid1; 
	string sid2; 
	string sid3; 
};
{t_Triple} triple;

execute {
for(var j1 in aJobs) for(var j2 in aJobs) for(var j3 in aJobs){
	if(j1!=j2 && j2!=j3 && j1!=j3
   	  && ((j1.t!="d" && j2.t!="d" && j1.e + j1.s + d[j1][j2] + j2.s + d[j2][j3] > j3.l)|| // distance must be smaller
   	  (j1.t=="c" && j2.t=="c" && j3.t=="c" && j1.q + j2.q + j3.q > C)||
   	  (j2.t=="c" && h*(d[j1][j2]+d[j2][j3]) > Q)))   // load must be smaller
	  triple.add(j1.sid,j2.sid,j3.sid);
  }
}

execute {
   cp.param.TimeMode = "ElapsedTime";
   cp.param.LogVerbosity=21;  
   cp.param.TimeLimit = 1;
 }

//dvar boolean X[pair];
dvar interval X[p in pair] optional in 0..T size p.d;

dvar interval eCG[fJobs] optional in 0..T*100 intensity EnergyPrice;
dvar int+ A[aJobs] ; //time of arrival
dvar int+ D[aJobs]; //time of departure from a node by Myoungju Park
dvar int+ U[aJobs]; //remaining cargo on arrival
dvar int+ Y[aJobs]; //remaining battery on arrival
dvar int+ CG[aJobs]; //amount of charge on a node by Myoungju Park
//dvar boolean S[aJobs][Times]; //1 if t*S[i][t] == A[j] and 0 otherwise by Myoungju Park
//dvar boolean F[aJobs][Times]; //1 if t*F[i][t] == D[j] and 0 otherwise by Myoungju Park
//dvar boolean L[aJobs][Times]; //S[i][t] - F[i][t] by Myoungju Park
dexpr float totDistance =
        sum(j in pair: j.sid1!="DN" && j.sid2!="D0" ) j.d * presenceOf(X[j]); // (1)
//dexpr float totCost =
//        sum(i in aJobs, t in Times: i.t=="f") ep[t] * L[i][t]; // (1-new-totCost by Myoungju Park)
dexpr float totCost = 1/60*
        sum(f in fJobs) sizeOf(eCG[f]) ; // (1-new-totCost by Myoungju Park)
      
dexpr float totVeh =          
         sum(j in pair: j.sid1=="D0" && (j.t2=="c" || j.t2=="f")) presenceOf(X[j]); 
       
//minimize totDistance + 1000*sum(j in pair: j.sid1=="D0" && (j.t2=="c" || j.t2=="f")) X[j]; //new objective value by Myoungju Park
//minimize totCost + totDistance + 10000000*totVeh; //new objective value by Myoungju Park
//minimize  totDistance + 10000000*totVeh; //new objective value by Myoungju Park
//minimize totVeh; 
//minimize staticLex(totVeh, totDistance); 
minimize staticLex(totVeh, totDistance,  totCost); 
subject to {
OptVehCnt==totVeh;
totDistance == OptDist ;//*1.1;
//totCost <= OptCost;
totVeh<=5;
  forall(f in fJobs, a in aJobs: f.id==a.id) { 
	startOf(eCG[f])  == A[a]*100;
	lengthOf(eCG[f]) == (D[a]-A[a])*100;
   }
   

//forall (i in aJobs: i.t=="c") sum(j in aJobs: i!=j && j.sid!="D0") X[i,j] == 1; // (2)
forall (i in aJobs: i.t=="c") 
	sum(j in aJobs, p in pair: i!=j && j.sid!="D0" &&
		i.id==p.id1 && j.id==p.id2) presenceOf(X[p]) == 1; // (2)
//forall (i in aJobs: i.t=="f") sum(j in aJobs: i!=j && j.sid!="D0") X[i,j] <= 1; // (3)
forall (i in aJobs: i.t=="f")
	sum(j in aJobs, p in pair: i!=j && j.sid!="D0" &&
		i.id==p.id1 && j.id==p.id2) presenceOf(X[p]) <= 1; // (3)

//forall (j in aJobs: j.t=="c" || j.t=="f")  	// (4)
// 	sum(i in aJobs: i!=j && i.sid!="D0") X[j,i] == sum(i in aJobs: i!=j && i.sid!="DN") X[i,j];
forall (j in aJobs: j.t=="c" || j.t=="f")  	// (4)
 	sum(i in aJobs, p in pair: i!=j && i.sid!="D0" && i.id==p.id2 && j.id==p.id1) presenceOf(X[p]) == 
	sum(i in aJobs, p in pair: i!=j && i.sid!="DN" && i.id==p.id1 && j.id==p.id2) presenceOf(X[p]);

//forall (i,j in aJobs: i!=j && (i.t=="c" || i.sid=="D0") && j.sid!="D0") // (5)
//	A[i]+(t[i,j]+i.s)*X[i,j] - l0*(1-X[i,j]) <= A[j]; 
forall (i,j in aJobs, p in pair: i!=j && (i.t=="c" || i.sid=="D0") && j.sid!="D0" && i.id==p.id1 && j.id==p.id2) // (5)
	A[i]+(t[i,j]+i.s)*presenceOf(X[p]) - l0*(1-presenceOf(X[p])) <= A[j]; 

//forall (i,j in aJobs: i!=j &&  i.t=="f" && j.sid!="D0") // (6)
//	A[i]+t[i,j]*X[i,j] + g*(Q-Y[i]) - (l0 + g*Q) * (1-X[i,j]) <= A[j]; 
//forall (i,j in aJobs, p in pair: i!=j &&  i.t=="f" && j.sid!="D0" && i.id==p.id1 && j.id==p.id2) // (6)
//	A[i]+t[i,j]*X[p] + g*(Q-Y[i]) - (l0 + g*Q) * (1-X[p]) <= A[j]; 
forall (i,j in aJobs, p in pair: i!=j &&  i.t=="f" && j.sid!="D0" && i.id==p.id1 && j.id==p.id2) // (new-6 by Myoungju Park)
// A[i]+t[i,j]*X[p] + g*CG[i] - (l0 + g*Q) * (1-X[p]) <= A[j]; 
	D[i]+t[i,j]*presenceOf(X[p]) - T * (1-presenceOf(X[p])) <= A[j];

	
forall (j in aJobs)  { 
	j.e <= A[j];
	A[j] <= j.l; // (7) <= j.l; // (7)
}

forall (i,j in aJobs, p in pair: i!=j &&  i.sid!="DN" && j.sid!="D0" && i.id==p.id1 && j.id==p.id2) // (8)
 	U[j] <= U[i] - i.q * presenceOf(X[p]) + C*(1-presenceOf(X[p]));

 
forall (j in aJobs: j.sid=="D0")  {
	U[j] == C; // (9)
	A[j] == 0;
	Y[j] == ftoi(round(Q/f));
	CG[j] == 0; //by Myoungju Park
}
   
forall (j in aJobs: j.sid=="DN") Y[j]==0;
     
forall (i,j in aJobs, p in pair: i!=j && (i.t=="c") && j.sid!="D0" && i.id==p.id1 && j.id==p.id2) // (10)
 	Y[j] <= Y[i] - (h*p.d) * presenceOf(X[p]) + Q/f*(1-presenceOf(X[p]));

forall (i,j in aJobs, p in pair: i!=j && (i.t=="f"||i.sid=="D0") && j.sid!="D0"  && i.id==p.id1 && j.id==p.id2) // (11)
 	Y[j] <= Y[i] + CG[i] - (h*p.d) * presenceOf(X[p]) + Q/f*(1-presenceOf(X[p])); //by Myoungju Park

//New constraints by Myoungju Park
forall (i in aJobs: i.t=="f") {
 //   sum(t in Times) S[i][t]==1;
//	A[i] == sum(t in Times) t*S[i][t];
 //   sum(t in Times) F[i][t]==1;
//	D[i] == sum(t in Times) t*F[i][t];
	Y[i] + CG[i] <= Q/f;
	D[i] >= g*CG[i]/f + A[i];
}

//forall (i in aJobs: i.t!="f") 
  //  Y[i]  <= ftoi(ceil(Q/f));
  //  Y[i]  <= ftoi(round(Q/f));

forall (tr in triple) 
	sum(p in pair: (p.sid1==tr.sid1 && p.sid2==tr.sid2) || (p.sid1==tr.sid2 && p.sid2==tr.sid3)) presenceOf(X[p]) <= 1;
	
}

execute {
writeln("totVehicle  = ", totVeh);
writeln("totDistance = ", totDistance);
writeln("totCost  	 = ", totCost);
writeln("i" +"\t" + "j"+"\t"+  "d" +"\t"+ "est" + "\t"+ "lst" + "\t" + "A" +"\t" + "D" +"\t" + "CG" +"\t" + "U" +"\t" + "Y" +"\t" + "q" +"\t" + "s");
for (var p in pair)
	if ( X[p].present) for (var j in aJobs) if(p.id2==j.id) 
      	writeln( p.sid1  +"\t"+  p.sid2  + "\t" + p.d 
                  + "\t" +p.e2 + "\t" + p.l2  + "\t" + A[j]  + "\t" + D[j]  + "\t" + CG[j] + "\t" + U[j]  + "\t" + Y[j] + "\t" +j.q+ "\t" +j.s) ;
}