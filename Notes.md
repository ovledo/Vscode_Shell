Vscode和GitHub连接方法:https://blog.csdn.net/qq_38981614/article/details/115013188

[报错解决] Failed to connect to github.com port 443 after ***** ms: Couldn‘t connect to server:https://blog.csdn.net/m0_64007201/article/details/129628363

https://blog.csdn.net/weixin_38233274/article/details/79257274
https://blog.csdn.net/yuxiaoxi21/article/details/89225339
https://www.cnblogs.com/FireLife-Cheng/p/16276876.html
https://farseerfc.me/zhs/history-of-chs-addressing.html
https://blog.csdn.net/weixin_43424368/article/details/106712500
[Python处理Excel]https://blog.csdn.net/weixin_44288604/article/details/120731317  
[Connect443报错]https://gitcode.csdn.net/65e6edff1a836825ed7887d5.html?dp_token=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpZCI6MTQ2NTkwNiwiZXhwIjoxNzExMzc2MDIwLCJpYXQiOjE3MTA3NzEyMjAsInVzZXJuYW1lIjoiaXJlbGlhWiJ9.uAcWwI6YKPuXR0bhKGeYFlPwtH5gWzCPE8GWUpBPIaw  




cat file.txt |grep IOPS |awk -F "=" '{print $2}' |awk '{if(NR==1) {line=$0} else {line=line","$0} } END{print line}'