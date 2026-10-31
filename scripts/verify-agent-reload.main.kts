#!/usr/bin/env kotlin
@file:DependsOn("com.google.code.gson:gson:2.11.0")
import com.google.gson.*
import java.nio.file.*
import java.time.Instant
import java.util.concurrent.TimeUnit

val root=Path.of(System.getProperty("user.dir")).toAbsolutePath()
val scratch=root.resolve("build/reload-integration/${System.currentTimeMillis()}")
Files.createDirectories(scratch)
val binary=scratch.resolve("InfrastructureAgent")
val compile=ProcessBuilder("xcrun","swiftc","-swift-version","5",root.resolve("app/ServerMonitor/InfrastructureAgent/main.swift").toString(),root.resolve("app/ServerMonitor/ServerMonitor/Support/ProcessRunner.swift").toString(),"-o",binary.toString()).inheritIO().start()
check(compile.waitFor()==0){"Supervisor compilation failed"}
val gson=GsonBuilder().setPrettyPrinting().create()
val config=scratch.resolve("infrastructure-agent.json")
val canary="SYNTHETIC-CREDENTIAL-DO-NOT-LOG"
// Short shell glue sets signal disposition, then exec retains one real owned PID.
val stubborn=listOf("/usr/bin/env","SYNTHETIC_SECRET=$canary","/bin/sh","-c","trap '' TERM; exec /bin/sleep 180")
val replacement=listOf("/usr/bin/env","SYNTHETIC_SECRET=$canary","/bin/sleep","181")
fun child(id:String,command:List<String>,policy:Boolean=false):Map<String,Any> = linkedMapOf<String,Any>("id" to id,"command" to command,"restartDelaySeconds" to 1).apply{if(policy)put("maxSilenceSeconds",300)}
val slow=mapOf("id" to "slow","command" to listOf("/bin/sleep","180"),"intervalSeconds" to 300,"timeoutSeconds" to 190,"runAtStart" to true)
val once=mapOf("id" to "once","command" to listOf("/usr/bin/true"),"intervalSeconds" to 300,"timeoutSeconds" to 10,"runAtStart" to true)
fun configure(children:List<Map<String,Any>>,jobs:Boolean=true,schema:Int=1){
 val body=mapOf("schema" to schema,"persistentChildren" to children,"scheduledJobs" to if(jobs)listOf(slow,once)else emptyList<Any>(),"watchNetworkChanges" to false)
 val next=scratch.resolve("next.json");Files.writeString(next,gson.toJson(body));Files.move(next,config,StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING)
}
configure(listOf(child("keep",stubborn)))
val launcher=ProcessBuilder(binary.toString()).redirectOutput(scratch.resolve("stdout.log").toFile()).redirectError(scratch.resolve("stderr.log").toFile())
launcher.environment()["SERVERMONITOR_INFRASTRUCTURE_ROOT"]=scratch.toString()
val agent=launcher.start()
val owned=mutableMapOf<Long,Instant?>()
fun remember(){ProcessHandle.of(agent.pid()).ifPresent{parent->parent.descendants().use{stream->stream.forEach{owned.putIfAbsent(it.pid(),it.info().startInstant().orElse(null))}}}}
fun alive(pid:Long)=ProcessHandle.of(pid).map{it.isAlive}.orElse(false)
fun status():JsonObject?=try{remember();JsonParser.parseString(Files.readString(scratch.resolve("status.json"))).asJsonObject}catch(_:Exception){null}
fun entries(s:JsonObject,key:String)=s.getAsJsonArray(key).map{it.asJsonObject}
fun pid(s:JsonObject,id:String)=entries(s,"children").firstOrNull{it["id"].asString==id&&it["running"].asBoolean}?.get("pid")?.asLong
fun runningJob(s:JsonObject)=entries(s,"scheduledJobs").any{it["id"].asString=="slow"&&it["running"].asBoolean}
fun await(label:String,seconds:Long=15,predicate:(JsonObject)->Boolean):JsonObject{
 val deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(seconds)
 while(System.nanoTime()<deadline){check(agent.isAlive){"Agent exited during $label"};val s=status();if(s!=null&&predicate(s)){println("PASS $label");return s};Thread.sleep(100)}
 error("Timed out: $label; evidence=$scratch")
}
try{
 val first=await("initial child and real scheduled processes"){pid(it,"keep")!=null&&runningJob(it)&&entries(it,"scheduledJobs").any{j->j["id"].asString=="once"&&j.has("lastRunAt")&&!j["running"].asBoolean}}
 val firstRun=entries(first,"scheduledJobs").first{it["id"].asString=="once"}["lastRunAt"]
 val keep=pid(first,"keep")!!
 val job=ProcessHandle.of(agent.pid()).get().children().use{it.filter{p->p.pid()!=keep}.findFirst().orElseThrow().pid()}
 configure(listOf(child("keep",stubborn),child("added",listOf("/bin/sleep","180"))))
 val added=await("add without restarting active work"){pid(it,"added")!=null&&pid(it,"keep")==keep&&runningJob(it)}
 check(alive(job)){"Unrelated scheduled process was stopped"};val addedPid=pid(added,"added")!!
 configure(listOf(child("keep",stubborn,true),child("added",listOf("/bin/sleep","180"))))
 Thread.sleep(2600);val policy=status()!!;check(pid(policy,"keep")==keep&&pid(policy,"added")==addedPid&&alive(job));println("PASS policy-only update preserves PIDs")
 configure(listOf(child("keep",stubborn,true)))
 await("remove only selected child"){pid(it,"keep")==keep&&!alive(addedPid)&&entries(it,"children").none{c->c["id"].asString=="added"}}
 check(alive(job))
 configure(listOf(child("keep",replacement,true)))
 val changed=await("replacement waits for old SIGTERM-resistant owner exit"){val p=pid(it,"keep");p!=null&&p!=keep&&!alive(keep)}
 val changedPid=pid(changed,"keep")!!;check(alive(job))
 check(entries(changed,"scheduledJobs").first{it["id"].asString=="once"}["lastRunAt"]==firstRun){"Unchanged idle job was resubmitted"};println("PASS unchanged idle schedule was not resubmitted")
 val log=Files.readString(scratch.resolve("logs/agent.log"));check(!log.contains(canary)){"Agent log exposed command credentials"};println("PASS command values absent from supervisor log")
 configure(listOf(child("keep",replacement)),schema=2)
 await("invalid config stops future work and retains active admission"){!it["configLoaded"].asBoolean&&runningJob(it)&&!alive(changedPid)}
 check(alive(job))
 configure(listOf(child("keep",replacement)))
 await("valid recovery retains in-flight scheduled owner"){it["configLoaded"].asBoolean&&pid(it,"keep")!=null&&runningJob(it)}
 Thread.sleep(2200);remember()
 val current=status()!!;val currentKeep=pid(current,"keep")!!
 val direct=ProcessHandle.of(agent.pid()).get().children().use{it.mapToLong{p->p.pid()}.toArray().toSet()}
 check(direct==setOf(currentKeep,job)){"Reload duplicated a scheduled producer"};println("PASS no duplicate scheduled producer after recovery")
 configure(listOf(child("keep",replacement)),jobs=false)
 Thread.sleep(2600)
 await("removed scheduled work drains visibly"){runningJob(it)&&pid(it,"keep")==currentKeep}
 check(alive(job))
 println("Infrastructure reload integration PASS; evidence=$scratch")
}finally{
 remember();agent.destroy();if(!agent.waitFor(10,TimeUnit.SECONDS)){agent.destroyForcibly();agent.waitFor()}
 for((id,birth) in owned)ProcessHandle.of(id).ifPresent{if(it.isAlive&&it.info().startInstant().orElse(null)==birth)it.destroyForcibly()}
}
