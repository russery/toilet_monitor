local DEBUG = true;

enum STATE {
    nobody,
    pee,
    poop,
    error
}
class detector {
    static MIN_RANGE = 3.0;
    static MAX_RANGE_POO = 8.0;
    static MAX_RANGE_PEE = 16.0;
    static MAX_RANGE = 100.0;
    static COUNT_THRESH = 5; // number of samples that must fall in a range bin
    
    pee_count = 0;
    poo_count = 0;
    state = STATE.nobody;
    
    constructor(){
        pee_count = 0;
        poo_count = 0;
        state = STATE.nobody;
    }

    // updates the state and returns it to the caller
    function detect_person(range_in) {
        if ((range_in < MIN_RANGE) || (range_in > MAX_RANGE)) {
            // range is invalid
            server.log("error: unexpected range value: " + range_in);
            state = STATE.error;
            pee_count = 0;
            poo_count = 0;
        }
        else if (range_in < MAX_RANGE_POO) {
            // range is valid and within poop range
            poo_count++;
            if (poo_count > COUNT_THRESH) {
                state = STATE.poop;
                poo_count = COUNT_THRESH;
                pee_count = 0;
            }
        }
        else if (range_in < MAX_RANGE_PEE) {
            // range is valid and in pee range
            pee_count++;
            if (pee_count > COUNT_THRESH) {
                state = STATE.pee;
                pee_count = COUNT_THRESH;
                poo_count = 0;
            }
        }
        else {
            poo_count--;
            pee_count--;
            if ((poo_count < 0) || (pee_count < 0)) {
                poo_count = 0;
                pee_count = 0;
                state = STATE.nobody;
            }
        }
        return state;
    }
}


function setup() {
     // only connect to the server by default in debug mode, to reduce power draw
    server.connect();
    
    trig <- hardware.pin9;
    trig.configure(DIGITAL_OUT, 0);
    
    echo <- hardware.pin1;
    echo.configure(DIGITAL_IN);
}

function getrange() {
    // get the start time
    local start_ms = hardware.millis();
    
    // send trigger pulse
    trig.write(0);
    trig.write(1);
    trig.write(0);
    
    // Wait for the echo pulse to start
    while(echo.read() == 0){
        if ((hardware.millis() - start_ms) > 500) {
            // TODO handle millis() rollover intelligently
            server.log("timeout on pulse start");
            start_ms = hardware.millis();
            break;
        }
    }
    local echobegin_us = hardware.micros();
    // Wait for the echo pulse to end
    while(echo.read() == 1){
        if ((hardware.millis() - start_ms) > 500){
            // TODO handle invalid ranges intelligently
            server.log("timeout on pulse end");
            break;
        }
    }
    local echolen_us = hardware.micros() - echobegin_us;
    
    return (echolen_us / 148.0);
}


// ------------------------------------------
// MAIN PROGRAM
// ------------------------------------------
local d = detector();
local prev_state = STATE.nobody;
local curr_state = STATE.nobody;
function mainloop() {
    local range_in = getrange();
    
    // detect state transitions
    prev_state = curr_state;
    curr_state = d.detect_person(range_in);
    if(curr_state != prev_state) {
        switch(curr_state){
            case STATE.nobody:
                server.log("nobody");
                break;
            case STATE.poop:
                server.log("poo");
                break;
            case STATE.pee:
                server.log("pee");
                break;
            default:
                server.log("error");
                break;
        }
    }
    
    agent.send("range", range_in);
    agent.send("state", curr_state);
    imp.wakeup(0.5, mainloop); 
}

setup(); 
mainloop();

