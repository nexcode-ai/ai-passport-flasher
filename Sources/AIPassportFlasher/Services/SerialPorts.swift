import Foundation
import IOKit
import IOKit.serial

struct SerialPort: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let productName: String?
    let vendorID: Int?
    let productID: Int?
    let serialNumber: String?

    var isUSBModem: Bool { (path as NSString).lastPathComponent.hasPrefix("cu.usbmodem") }
    var isEspressifJTAG: Bool { vendorID == DeviceSpec.espressifVID && productID == DeviceSpec.usbSerialJtagPID }

    var displayName: String {
        var s = (path as NSString).lastPathComponent
        if let p = productName { s += " · \(p)" }
        return s
    }

    var detail: String {
        var parts: [String] = []
        if let v = vendorID, let p = productID { parts.append(String(format: "VID %04X / PID %04X", v, p)) }
        if let sn = serialNumber, !sn.isEmpty { parts.append("USB 序列号 \(sn)") }
        return parts.joined(separator: " · ")
    }
}

enum SerialPortScanner {
    /// Lists callout (`/dev/cu.*`) serial devices; `onlyUSBModem` keeps `cu.usbmodem*`.
    static func scan(onlyUSBModem: Bool = true) -> [SerialPort] {
        var result: [SerialPort] = []
        guard let matching = IOServiceMatching(kIOSerialBSDServiceValue) else { return fallbackScan(onlyUSBModem) }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return fallbackScan(onlyUSBModem)
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
            guard let path = stringProperty(service, kIOCalloutDeviceKey) else { continue }
            let port = SerialPort(
                path: path,
                productName: searchParents(service, "USB Product Name") as? String ?? searchParents(service, "kUSBProductString") as? String,
                vendorID: (searchParents(service, "idVendor") as? NSNumber)?.intValue,
                productID: (searchParents(service, "idProduct") as? NSNumber)?.intValue,
                serialNumber: searchParents(service, "USB Serial Number") as? String ?? searchParents(service, "kUSBSerialNumberString") as? String
            )
            if onlyUSBModem && !port.isUSBModem { continue }
            result.append(port)
        }
        return result.sorted { a, b in
            if a.isEspressifJTAG != b.isEspressifJTAG { return a.isEspressifJTAG }
            return a.path < b.path
        }
    }

    private static func fallbackScan(_ onlyUSBModem: Bool) -> [SerialPort] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        return names
            .filter { $0.hasPrefix(onlyUSBModem ? "cu.usbmodem" : "cu.") }
            .sorted()
            .map { SerialPort(path: "/dev/\($0)", productName: nil, vendorID: nil, productID: nil, serialNumber: nil) }
    }

    private static func stringProperty(_ service: io_object_t, _ key: String) -> String? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
    }

    private static func searchParents(_ service: io_object_t, _ key: String) -> Any? {
        IORegistryEntrySearchCFProperty(
            service, kIOServicePlane, key as CFString, kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        )
    }
}
