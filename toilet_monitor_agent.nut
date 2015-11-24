local range_in = null;
local state = null;

const html1 = @"<!DOCTYPE html>
<html lang=""en"">
    <head>
        <meta charset=""utf-8"">
        <meta name=""viewport"" content=""width=device-width, initial-scale=1, maximum-scale=1, user-scalable=0"">
        <meta name=""apple-mobile-web-app-capable"" content=""yes"">
        <script src=""http://code.jquery.com/jquery-1.9.1.min.js""></script>
        <script src=""http://code.jquery.com/jquery-migrate-1.2.1.min.js""></script>
        <script src=""http://d2c5utp5fpfikz.cloudfront.net/2_3_1/js/bootstrap.min.js""></script>
        
        <link href=""//d2c5utp5fpfikz.cloudfront.net/2_3_1/css/bootstrap.min.css"" rel=""stylesheet"">
        <link href=""//d2c5utp5fpfikz.cloudfront.net/2_3_1/css/bootstrap-responsive.min.css"" rel=""stylesheet"">

        <title>Pooper Trooper</title>
    </head>
    <body>
        <div class='container'>
            <div class='well' style='max-width: 300px; margin: 0 auto 10px; text-align:center;'>
                <h1>Toilet Range<h1>
                <h3>Range: ";
const html2 = @" inches</h3>
            </div>
        </div>
    </body>
</html>";


http.onrequest(function(request, response) { 
    if (request.body == "") {
        local html = format(html1 + ("%s", range_in) + html2);
        response.send(200, html);
    }
    else {
        response.send(500, "Internal Server Error");
    }     
});

device.on("range", function(r){range_in=r;});
device.on("state", function(s){state=s;});