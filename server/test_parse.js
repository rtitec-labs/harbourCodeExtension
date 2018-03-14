var provider = require('./src/provider.js');

var p = new provider.Provider();
p.parseFile("../test/dbg_test.prg").then(()=>
{
    for (var fn in p.funcList) {
        if (p.funcList.hasOwnProperty(fn)) {
            var info = p.funcList[fn];
            var msg = `${info.kind}: ${info.name}`;
            if(info.parent)
            {
                msg+= ` of ${info.parent.name}`
            }
            msg+= ` in ${info.document}(${info.startLine}:${info.startCol})-(${info.endLine}:${info.endCol})`
            console.log(msg)
        }
    }
    process.exit();
});
