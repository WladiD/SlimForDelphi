# Two minute example

## How to run this example
1. Build the project **TwoMinuteExample.dproj** an run it.  
   It listen on the port 9000.
1. Download **fitnesse-standalone.jar** from  
   https://fitnesse.org/FitNesseDownload.html
1. Run FitNesse with following parameters:  
   `java -Dslim.port=9000 -Dslim.pool.size=1 -jar fitnesse-standalone.jar`
1. Go to: http://localhost/FitNesse.UserGuide.TwoMinuteExample
1. Click the **Test** link in the header  
   This example application should react to the request and response and log!  
   That's it.
