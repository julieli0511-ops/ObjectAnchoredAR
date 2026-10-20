import UIKit
final class ChatViewController: UIViewController {
    private let content = UILabel(); private let status = UILabel(); private let start = Date()
    override func viewDidLoad() { super.viewDidLoad(); title = "2D Conversational"; view.backgroundColor = .black
        let header = UILabel(); header.text = "AI INTERPRETATION"; header.textColor = InterfaceStyle.accent; header.font = .systemFont(ofSize: 12, weight: .bold); header.textAlignment = .center
        content.numberOfLines = 0; content.textColor = .white; content.font = .systemFont(ofSize: 18, weight: .regular); content.translatesAutoresizingMaskIntoConstraints = false
        let glass = InterfaceStyle.glassCard(); glass.translatesAutoresizingMaskIntoConstraints = false; glass.contentView.addSubview(content)
        NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor, constant: 22),content.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor, constant: -22),content.topAnchor.constraint(equalTo: glass.contentView.topAnchor, constant: 22),content.bottomAnchor.constraint(equalTo: glass.contentView.bottomAnchor, constant: -22)])
        let actions = UIStackView(arrangedSubviews: [button("That's correct", "checkmark.circle.fill", #selector(confirm), true),button("Correct interpretation", "pencil.circle", #selector(correct))]); actions.axis = .vertical; actions.spacing = 10
        status.textColor = .secondaryLabel; status.textAlignment = .center; status.font = .preferredFont(forTextStyle: .footnote)
        let stack = UIStackView(arrangedSubviews: [header, glass, actions, status]); stack.axis = .vertical; stack.spacing = 16; stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
        refresh()
    }
    private func button(_ title:String,_ symbol:String,_ action:Selector,_ filled:Bool = false)->UIButton { let b=InterfaceStyle.pillButton(title,symbol:symbol,filled:filled);b.addTarget(self,action:action,for:.touchUpInside);return b }
    private func refresh(){content.text = "Your question\n\(InterpretationStore.shared.value.question)\n\n\(InterpretationStore.shared.value.text)"}
    @objc private func confirm(){InterpretationStore.shared.record(condition:"2D",outcome:"confirmed",selectedIntendedTarget:false,start:start);status.text="Response saved"}
    @objc private func correct(){let a=UIAlertController(title:"Correct interpretation",message:"Select the intended target.",preferredStyle:.actionSheet);["Coffee cup","Water bottle","Notebook"].forEach { option in a.addAction(UIAlertAction(title:option,style:.default){_ in InterpretationStore.shared.value.interpretedTarget=option;InterpretationStore.shared.value.interpretedLocation=option == "Coffee cup" ? "Left side of the laptop" : "Right side of the laptop";InterpretationStore.shared.record(condition:"2D",outcome:"corrected",selectedIntendedTarget:option == "Coffee cup",start:self.start);self.refresh()})};a.addAction(UIAlertAction(title:"Cancel",style:.cancel));present(a,animated:true)}
}
