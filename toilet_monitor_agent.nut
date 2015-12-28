local range_in = null;
local state = null;
local batt_volts = 0.0;
local batt_soc_percent = 0.0;

const html1 = @"<!DOCTYPE html>
<html lang=""en"">
    <head>
        <title>Pooper Trooper</title>
    </head>
    <body>
        <div class='container'>
            <div class='well' style='max-width: 300px; margin: 0 auto 10px; text-align:center;'>
                <h1>Toilet Range<h1>
                <h3>Range: ";
const html2 = @" inches</h3>
                <h3>State: ";
const html3 = @"</h3>
                <h3>Batt Voltage: ";
const html4 = @"volts</h3>
                <h3>Batt SoC: ";
const html5 = @"%%</h3>
            </div>
        </div>
    </body>
</html>";


http.onrequest(function(request, response) { 
    if (request.body == "") {
        local html = format( html1 +
                            ("%s", range_in) + html2 +
                            ("%s", state) + html3 +
                            ("%s", batt_volts) + html4 +
                            ("%s", batt_soc_percent) + html5 );
        response.send(200, html);
    }
    else {
        response.send(500, "Internal Server Error");
    }     
});

device.on("range", function(r){range_in=r;});
device.on("state", function(s){state=s;});
device.on("battery_status", function(b){batt_soc_percent=b[0]; batt_volts=b[1]})
