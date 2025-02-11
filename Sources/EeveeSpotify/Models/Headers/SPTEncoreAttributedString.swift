import Foundation

@objc protocol SPTEncoreAttributedString {
    func initWithString(_ string: String, typeStyle: SPTEncoreTypeStyle, attributes: SPTEncoreAttributes) -> SPTEncoreAttributedString
    // new method since 9.0.14
    func initWithString(_ string: String, textStyle: SPTEncoreTypeStyle, attributes: SPTEncoreAttributes) -> SPTEncoreAttributedString
    
    func text() -> String
    
    @available(iOS 15.0, *)
    func typeStyle() -> SPTEncoreTypeStyle
    
    @available(iOS 15.0, *)
    func attributes() -> SPTEncoreAttributes
}
