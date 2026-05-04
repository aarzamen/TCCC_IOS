import Foundation

enum DemoScenarios {
    /// scenario_1_gsw_thigh — single casualty, GSW right thigh, full MARCH +
    /// vitals in spoken form.
    static let scenario1: String = """
        Alright, approaching the casualty now. I can see significant bleeding from the right thigh area. Looks like a gunshot wound to the right upper thigh. Applying a tourniquet now, CAT tourniquet, right thigh, high and tight. Time of application is fourteen thirty-two. Okay tourniquet is on, bleeding appears controlled.

        Moving to airway. Patient is conscious, talking to me, airway is patent.

        Checking respirations. Breath sounds bilateral and equal, chest rise symmetric, respiratory rate looks about eighteen. No signs of pneumothorax.

        Checking circulation. Radial pulse is present, maybe a little fast, skin is warm and slightly diaphoretic. Starting an IV, eighteen gauge, left AC.

        Head check. Patient is alert, oriented, pupils equal and reactive. No signs of head injury. Wrapping the patient to prevent hypothermia.

        Vitals: heart rate one ten, blood pressure ninety over sixty, pulse ox ninety-six percent, respiratory rate eighteen.
        """

    /// scenario_4_femur_fracture — closed femur fracture, traction splint,
    /// urgent classification.
    static let scenario4: String = """
        Corpsman up! We got a Marine down at range four hundred. He was running between positions and his leg just gave out. He went down hard. He's on the ground, conscious, in a lot of pain.

        Okay, checking for hemorrhage first. I don't see any external bleeding. His right thigh is visibly deformed, swollen. This looks like a mid-shaft femur fracture. No open wound though, so no tourniquet needed at this time. But I'm watching for swelling because you can lose a lot of blood internally with a femur fracture.

        Airway is patent, he's yelling at me, so that's good. Breathing is normal, bilateral breath sounds clear, no chest trauma. Radial pulse is present and strong right now. Skin is warm but he's starting to sweat. Starting an IV, eighteen gauge, right AC, running normal saline.

        He's alert, oriented, GCS fifteen. Pupils equal and reactive. No head injury, he just fell. Wrapping him up to prevent hypothermia, it's cold out here even in the desert at night.

        Splinting the right leg now. Traction splint, Sager, applied to the right lower extremity. He says the pain is about an eight out of ten. Giving him the combat pill pack, Tylenol and Meloxicam.

        Vitals: heart rate one hundred and five, blood pressure one hundred over sixty-eight, pulse ox ninety-seven, respiratory rate twenty.

        This is an urgent casualty, possible femur fracture, internal bleeding risk.
        """
}
