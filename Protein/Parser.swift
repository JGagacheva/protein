//
//  Parser.swift
//  Protein
//
//  Created by Jana on 10/18/23.
//

import Foundation

struct Atom {
    var type: String
    var x: Float
    var y: Float
    var z: Float
}

////reading
func parsePDB(url: URL) -> Array<Atom> {
    var strings: [String] = []
    var newLine: [Float] = []
    var atom: String = ""
    var atoms: Array<Atom> = []
    
    do {
        let file = try String(contentsOf: url, encoding: .utf8)
        let lines = file.split(whereSeparator: \.isNewline)
        
        for line in lines {
            if (line.prefix(4) == "ATOM") {
                
                strings = line.components(separatedBy: .whitespaces).filter({ s in s != "" })
                atom = strings[strings.count - 1]
                /// convert values to floats
                newLine = strings.map{
                    ($0 as NSString).floatValue
                }
                atoms.append(.init(
                    type: atom,
                    x: newLine[6],
                    y: newLine[7],
                    z: newLine[8]
                ))
            }
        }
    } catch {
        print("The file reading failed with error: \(error)")
    }
//    for atom in atoms {
//        print(atom)
//    }
    return atoms
}


