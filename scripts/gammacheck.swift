import CoreGraphics

var count: UInt32 = 0
CGGetActiveDisplayList(0, nil, &count)
var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
CGGetActiveDisplayList(count, &displays, &count)

for d in displays {
    let size = 256
    var r = [CGGammaValue](repeating: 0, count: size)
    var g = [CGGammaValue](repeating: 0, count: size)
    var b = [CGGammaValue](repeating: 0, count: size)
    var n: UInt32 = 0
    let res = CGGetDisplayTransferByTable(d, UInt32(size), &r, &g, &b, &n)
    let builtin = CGDisplayIsBuiltin(d) != 0 ? "built-in" : "external"
    if res == .success, n > 0 {
        let i = Int(n) - 1
        print("display \(d) [\(builtin)]  max R=\(r[i])  G=\(g[i])  B=\(b[i])")
    } else {
        print("display \(d) [\(builtin)]  gamma read failed (\(res.rawValue))")
    }
}
