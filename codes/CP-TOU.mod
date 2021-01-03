using CP;
int OptVehCnt=2;
//int OptDist=...;
int nv = 2; // Number of Trucks
range Trucks = 1..nv;

float QQ=...;
float gg=...;
float scale=100;
int Q=ftoi(ceil(QQ*scale)); //77.5; // Vehicle fuel tank capacity
int g=ftoi(ceil(gg*scale));//  3.47; //inverse refueling rate
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


{int} Nodes;
execute {
var i=1;
for(var j in Jobs) {
    if(j.t=="c") aJobs.add(i++,j.sid,j.t,j.x,j.y,j.q,j.e,j.l,j.s )
    Nodes.add(i-1);
    if(j.t=="f") { for(var v=1;v<=nv;v++) {
    	aJobs.add(i++,j.sid + 1,j.t,j.x,j.y,j.q,j.e,j.l,j.s ); Nodes.add(i-1);
    	aJobs.add(i++,j.sid + 1,j.t,j.x,j.y,j.q,j.e,j.l,j.s ); Nodes.add(i-1);//dummy fuel
      }    	
    }                              
}
var k=1001; //depot
for(var j in Jobs) {
    if(j.t=="d") for(var v=1;v<=nv;v++) {
      aJobs.add(k,j.sid,"d",j.x,j.y,j.q,j.e,j.l,j.s ); Nodes.add(k); //depot depart
      aJobs.add(k+1000,"DN","r",j.x,j.y,j.q,j.e,j.l,j.s); Nodes.add(k+1000); //depot return
      k++;
    }
} 
}
{t_augJob} fJobs= {i | i in aJobs : i.t=="f"};

tuple triplet {key int c1; key int c2; int d; };
{triplet} Dist = {
   <i.id, j.id, ftoi(round(sqrt((i.x-j.x)*(i.x-j.x)+(i.y-j.y)*(i.y-j.y)))) > 
    | i, j in aJobs  };//: i.id != j.id
int dNtoN[Nodes][Nodes];
execute {
for(var i in aJobs) for(var j in aJobs)
  dNtoN[i.id][j.id]= Opl.ftoi(Opl.round ( Opl.sqrt( (i.x-j.x)*(i.x-j.x)+(i.y-j.y)*(i.y-j.y))));
};

int T = max(j in aJobs) j.l;
range Times = 0..T-1;  
int p[0..23]=[26,26,27,26,26,29,36,46,44,39,53,47,42,42,40,39,48,67,78,80,81,73,63,48];
int ep[Times]; //minute by minute pricing
execute {
var i;
var k;
for(var t in Times){
  //writeln(t, "__", Opl.floor(t/60), "__", (Opl.floor(t/60) % 24) );	
  ep[t]=p[(Opl.floor(t/60) % 24)];
}	 
}
stepFunction EnergyPrice = stepwise(t in Times) { ep[t]-> t*100; ep[0]};


dvar interval itvJob[j in aJobs] optional(j.t=="f");
dvar interval itvJ2T[j in aJobs][Trucks] optional;
dvar interval eCG[fJobs] optional in 0..T*100 intensity EnergyPrice;

dvar sequence seqTrk[t in Trucks] 
     in   all(j in aJobs) itvJ2T[j][t] 
     types all(j in aJobs) j.id;

cumulFunction discharges[j in aJobs][t in Trucks] = -stepAtStart (itvJ2T[j][t], 0, Q);
dexpr float dischargeExprs[j in aJobs][t in Trucks] = heightAtStart(itvJ2T[j][t], discharges[j][t]);
dvar int dischargeValues[j in aJobs][t in Trucks] in -Q..0;

cumulFunction charges[j in aJobs][t in Trucks] = stepAtEnd (itvJ2T[j,t], 0, j.t=="f" ? Q : 0);
dexpr float chargeExprs[j in aJobs][t in Trucks] = heightAtEnd(itvJ2T[j][t], charges[j][t]);
dvar int chargeValues[j in aJobs][t in Trucks] in 0..Q;                          
                               
cumulFunction cumBattery[t in Trucks]=  step(0, Q)  // initial battery level
    + sum(j in aJobs) discharges[j][t]
    + sum(j in aJobs) charges[j][t];
                         
dvar int predecessor[t in Trucks][j in aJobs];

dexpr float totDistance = 1/scale*
        sum(j in aJobs, t in Trucks) -dischargeValues[j][t]; // dNtoN[j.id][predecessor[t][j]];       

dvar int bVehicleUsed[Trucks];        
dexpr float totVeh = sum( t in Trucks) bVehicleUsed[t];
dexpr float totCost = 1/60* sum(f in fJobs) sizeOf(eCG[f]); 
execute {
    var f = cp.factory;
   // var phase = f.searchPhase(seqTrk);
   // cp.setSearchPhases(phase);
}
execute {
   cp.param.TimeMode = "ElapsedTime";
   cp.param.LogPeriod=100000;
   //cp.param.Workers=2;
   cp.param.FailureDirectedSearchEmphasis = 0.99;
   cp.param.TimeLimit = 30;
}

//minimize totDistance;
minimize staticLex(totVeh, totDistance);
//minimize staticLex(totVeh, totDistance,  totCost); 
constraints {


forall(f in fJobs, a in aJobs: f.id==a.id) { 
	startOf(eCG[f])  == startOf(itvJob[a])*100;
	lengthOf(eCG[f]) == lengthOf(itvJob[a])*100;
 } 
   
forall(j in aJobs){
    alternative(itvJob[j], all(t in Trucks) itvJ2T[j][t] );
    startOf(itvJob[j], j.e) >= j.e;
    startOf(itvJob[j], j.l) <= j.l;
}              
forall(t in Trucks) //truck capacity
  sum(j in aJobs) presenceOf(itvJ2T[j][t] )*j.q <= C;

forall(j in aJobs,t in Trucks) {
 // Store predecessor in a variable so that the search can work on them:
 predecessor[t][j] == typeOfPrev(seqTrk[t], itvJ2T[j][t], j.id, j.id);

 //Battery consumption
 dischargeValues[j][t] == - scale*dNtoN[j.id][predecessor[t][j]];
 dischargeValues[j][t] ==  dischargeExprs[j][t];
 
 // A job cannot be predecessor of itself. Except for the case it is first or absent:
 if (j.t != "d")
   presenceOf(itvJ2T[j][t]) == (predecessor[t][j] != j.id);
 //if (j.id==29) presenceOf(itvJ2T[j][t]) == (predecessor[t][j] != 25);
 //if (j.id==25) presenceOf(itvJ2T[j][t]) => (predecessor[t][j] != 29);
 //if (j.id==27) presenceOf(itvJ2T[j][t]) => (predecessor[t][j] != 25);
 //if (j.id==25) presenceOf(itvJ2T[j][t]) => (predecessor[t][j] != 27);
 
   
 // Charging should not be the first stop after the depot:
// if (j.t == "f")
 //  predecessor[t][j] != 1001;  
}

forall(j in aJobs,t in Trucks: j.t=="f")        //Battery charging
  	chargeValues[j][t] == g*sizeOf(itvJ2T[j][t]);

forall(j in aJobs,t in Trucks)
    chargeValues[j][t] == chargeExprs[j][t];


forall(j in aJobs: j.t=="c")
	 sizeOf(itvJob[j]) == j.s;
forall(j in aJobs: j.t=="d" || j.t=="r")
	 sizeOf(itvJob[j]) == 0;
	 	 
forall (j in aJobs, t in Trucks: j.t=="d" && j.id==1000+t){ 
	presenceOf(itvJ2T[j][t])==1; 
	first(seqTrk[t],itvJ2T[j][t] ); 
} 
forall (j in aJobs, t in Trucks: j.t=="r" && j.id==2000+t){ 
	presenceOf(itvJ2T[j][t])==1; 
	last(seqTrk[t],itvJ2T[j][t] );
   // sizeOf(itvJ2T[j][t]) == 0;
}

forall(t in Trucks) {
  noOverlap(seqTrk[t],Dist);   
  cumBattery[t] <= Q;
}
//sum(t in Trucks,j in aJobs) chargeValues[j][t] + totVeh*Q == totDistance*scale;

forall(v in Trucks, j in aJobs: j.t=="c" )
	presenceOf(itvJ2T[j][v]) <= bVehicleUsed[v];	

}


// Event is a change of cumulative function for a given truck. Events with detla_y=0 are omitted.
// Events are sorted so that we can easily scan them and compute the cumulative function:
tuple Event { 
  int x;        // Time of the event
  string type;  // "s" for start event, "e" for end event
  int delta_y;  // Change in the battery level
  string sid;   // Sid of the job
};
sorted {Event} events[t in Trucks] =
  { <endOf(itvJ2T[j][t]), "s", chargeValues[j][t], j.sid> | j in aJobs: presenceOf(itvJ2T[j][t]) && j.t != "d" }
  union
  { <startOf(itvJ2T[j][t]), "e", dischargeValues[j][t], j.sid> | j in aJobs: presenceOf(itvJ2T[j][t]) && j.t != "d" };

execute {
writeln("totVehicle  = ", totVeh);
writeln("totDistance = ", totDistance);
writeln("totCost  	 = ", totCost);
writeln("v" +"\t" + "j"+"\t" + "est" + "\t"+ "lst" + "\t" + "s" +"\t" + "e"  + "\t" + "q" +"\t" + "s");

for (var v in Trucks)  
for (var j in aJobs) 
	if (itvJ2T[j][v].present) 
      	writeln( v +"\t"+ j.sid +"\t"+  j.e +"\t"+ j.l + "\t" +  itvJ2T[j][v].start + "\t" +  itvJ2T[j][v].end + "\t" + j.q +"\t"+  j.s );      	
      	 
      	   
  for (var t = 1; t <= nv; t++) {
    writeln("Truck ", t, " events: ");
    writeln("  (Battery starts charged with level ", Q / scale, ".)");
    for (e in events[t]) {
      write("  Time ", e.x, " at ", e.sid, " ");
      if (e.delta_y > 0)
        writeln("charging +", e.delta_y / scale);
      else if (e.delta_y < 0)
        writeln("discharging ", e.delta_y / scale);
      else
        writeln("(no change)");
    }
    writeln();
    writeln("Truck ", t, " cumBattery levels: ");
    // Battery starts charged by value Q:
    var cumulValue = Q;
    var prevX = 0;
    // We are going to scan the events in chronological order. Value of the
    // cumul function is printed only:
    // * after processing all events that happens at the same time x.
    // * and only if the value is different from the previous value printed
    //   (i.e. segments with the same value are merged).
    var lastPrintedValue = -1; // To detect consecutive segments with the same value
    for (e in events[t]) {
      if (e.x != prevX) {
        // We processed all events happening at time "prevX". The value at
        // "prevX" is "cumulValue".
        if (cumulValue != lastPrintedValue) {
          // The segment has different value then the previous segment. Print it.
          writeln("  From time ", prevX, " value ", cumulValue / scale);
          lastPrintedValue = cumulValue;
        }
      }
      cumulValue += e.delta_y;
      prevX = e.x;
    }
    // Print the final value of the cumulative function. But only if the
    // segment has different value then the previous segment:
    if (cumulValue != lastPrintedValue)
      writeln("  From time ", prevX, " value ", cumulValue/scale);
    writeln();
  }
}
