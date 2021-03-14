//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import Lottie

@objc
public enum PaymentsSettingsMode: UInt {
    case inAppSettings
    case standalone
}

// MARK: -

@objc
public class PaymentsSettingsViewController: OWSTableViewController2 {

    private let mode: PaymentsSettingsMode

    private let paymentsHistoryDataSource = PaymentsHistoryDataSource()

    fileprivate static let maxHistoryCount: Int = 4

    @objc
    public required init(mode: PaymentsSettingsMode) {
        self.mode = mode

        super.init()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        useThemeBackgroundColors = true

        title = NSLocalizedString("SETTINGS_PAYMENTS_TITLE",
                                  comment: "Label for the 'payments' section of the app settings.")

        if mode == .standalone {
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done,
                                                               target: self,
                                                               action: #selector(didTapDismiss),
                                                               accessibilityIdentifier: "dismiss")
        }

        addListeners()

        updateTableContents()

        updateNavbar()

        paymentsHistoryDataSource.delegate = self
    }

    private func updateNavbar() {
        if paymentsSwift.arePaymentsEnabled {
            let moreOptionsIcon = UIImage(named: "more-horiz-24")?.withRenderingMode(.alwaysTemplate)
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                image: moreOptionsIcon,
                landscapeImagePhone: nil,
                style: .plain,
                target: self,
                action: #selector(didTapSettings)
            )
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateTableContents()
        updateNavbar()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        paymentsSwift.updateCurrentPaymentBalance()
        paymentsCurrencies.updateConversationRatesIfStale()
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        if isMovingFromParent,
           mode == .inAppSettings {
            PaymentsViewUtils.markAllUnreadPaymentsAsReadWithSneakyTransaction()
        }
    }

    private func addListeners() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(arePaymentsEnabledDidChange),
            name: PaymentsImpl.arePaymentsEnabledDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateTableContents),
            name: PaymentsImpl.currentPaymentBalanceDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateTableContents),
            name: PaymentsCurrenciesImpl.paymentConversionRatesDidChange,
            object: nil
        )
    }

    @objc
    private func arePaymentsEnabledDidChange() {
        updateTableContents()
        updateNavbar()

        if !Self.payments.arePaymentsEnabled {
            presentToast(text: NSLocalizedString("SETTINGS_PAYMENTS_PAYMENTS_DISABLED_TOAST",
                                                 comment: "Message indicating that payments have been disabled in the app settings."))
        }
    }

    @objc
    private func updateTableContents() {
        AssertIsOnMainThread()

        let arePaymentsEnabled = paymentsSwift.arePaymentsEnabled
        if arePaymentsEnabled {
            updateTableContentsEnabled()
        } else {
            updateTableContentsNotEnabled()
        }
    }

    private func updateTableContentsEnabled() {
        AssertIsOnMainThread()

        let contents = OWSTableContents()

        let headerSection = OWSTableSection()
        headerSection.hasBackground = false
        headerSection.add(OWSTableItem(customCellBlock: { [weak self] in
            let cell = OWSTableItem.newCell()
            self?.configureEnabledHeader(cell: cell)
            return cell
        },
        actionBlock: {
            Self.paymentsSwift.updateCurrentPaymentBalance()
            Self.paymentsCurrencies.updateConversationRatesIfStale()
        }))
        contents.addSection(headerSection)

        let historySection = OWSTableSection()
        configureHistorySection(historySection, paymentsHistoryDataSource: paymentsHistoryDataSource)
        contents.addSection(historySection)

        addHelpCards(contents: contents)

        self.contents = contents
    }

    private func configureEnabledHeader(cell: UITableViewCell) {
        let balanceLabel = UILabel()
        balanceLabel.font = UIFont.ows_dynamicTypeLargeTitle1Clamped.withSize(54)
        balanceLabel.textAlignment = .center
        balanceLabel.adjustsFontSizeToFitWidth = true

        let balanceWrapper = UIView.container()
        balanceWrapper.addSubview(balanceLabel)
        balanceLabel.autoPinEdgesToSuperviewEdges()

        let conversionRefreshSize: CGFloat = 20
        let conversionRefreshIcon = UIImageView.withTemplateImageName("refresh-20",
                                                                      tintColor: Theme.primaryIconColor)
        conversionRefreshIcon.autoSetDimensions(to: .square(conversionRefreshSize))

        let conversionLabel = UILabel()
        conversionLabel.font = UIFont.ows_dynamicTypeSubheadlineClamped
        conversionLabel.textColor = Theme.secondaryTextAndIconColor

        let conversionStack1 = UIStackView(arrangedSubviews: [
            conversionRefreshIcon,
            conversionLabel
        ])
        conversionStack1.axis = .horizontal
        conversionStack1.alignment = .center
        conversionStack1.spacing = 12

        let conversionStack2 = UIStackView(arrangedSubviews: [ conversionStack1 ])
        conversionStack2.axis = .vertical
        conversionStack2.alignment = .center

        func hideConversions() {
            conversionRefreshIcon.tintColor = .clear
            conversionLabel.text = " "
        }

        if let paymentBalance = Self.paymentsSwift.currentPaymentBalance {
            balanceLabel.attributedText = PaymentsFormat.attributedFormat(paymentAmount: paymentBalance.amount,
                                                                          isShortForm: false)

            if let balanceConversionText = Self.buildBalanceConversionText(paymentBalance: paymentBalance) {
                conversionLabel.text = balanceConversionText
            } else {
                hideConversions()
            }
        } else {
            // Use an empty string to avoid jitter in layout between the
            // "pending balance" and "has balance" states.
            balanceLabel.text = " "

            let activityIndicator = UIActivityIndicatorView(style: .gray)
            balanceWrapper.addSubview(activityIndicator)
            activityIndicator.autoCenterInSuperview()
            activityIndicator.startAnimating()

            hideConversions()
        }

        let addMoneyButton = buildHeaderButton(title: NSLocalizedString("SETTINGS_PAYMENTS_ADD_MONEY",
                                                                        comment: "Label for 'add money' view in the payment settings."),
                                               iconName: "plus-24",
                                               selector: #selector(didTapAddMoneyButton))
        let sendPaymentButton = buildHeaderButton(title: NSLocalizedString("SETTINGS_PAYMENTS_SEND_PAYMENT",
                                                                           comment: "Label for 'send payment' button in the payment settings."),
                                                  iconName: "send-mob-24",
                                                  selector: #selector(didTapSendPaymentButton))
        let buttonStack = UIStackView(arrangedSubviews: [
            addMoneyButton,
            sendPaymentButton
        ])
        buttonStack.axis = .horizontal
        buttonStack.spacing = 8
        buttonStack.alignment = .fill
        buttonStack.distribution = .fillEqually

        let headerStack = UIStackView(arrangedSubviews: [
            balanceWrapper,
            UIView.spacer(withHeight: 8),
            conversionStack2,
            UIView.spacer(withHeight: 44),
            buttonStack
        ])
        headerStack.axis = .vertical
        headerStack.alignment = .fill
        headerStack.layoutMargins = UIEdgeInsets(top: 30,
                                                 leading: OWSTableViewController2.cellHOuterMargin * 2,
                                                 bottom: 20,
                                                 trailing: OWSTableViewController2.cellHOuterMargin * 2)
        headerStack.isLayoutMarginsRelativeArrangement = true
        headerStack.addBackgroundView(withBackgroundColor: Theme.tableView2BackgroundColor)
        cell.contentView.addSubview(headerStack)
        headerStack.autoPinEdgesToSuperviewEdges()
    }

    private func buildHeaderButton(title: String, iconName: String, selector: Selector) -> UIView {

        let iconView = UIImageView.withTemplateImageName(iconName,
                                                         tintColor: Theme.primaryIconColor)
        iconView.autoSetDimensions(to: .square(24))

        let label = UILabel()
        label.text = title
        label.textColor = Theme.primaryTextColor
        label.font = .ows_dynamicTypeCaption2Clamped

        let stack = UIStackView(arrangedSubviews: [
            iconView,
            label
        ])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 5
        stack.layoutMargins = UIEdgeInsets(top: 12, leading: 20, bottom: 6, trailing: 20)
        stack.isLayoutMarginsRelativeArrangement = true
        stack.isUserInteractionEnabled = true
        stack.addGestureRecognizer(UITapGestureRecognizer(target: self, action: selector))

        let backgroundView = UIView()
        backgroundView.backgroundColor = Theme.tableCell2BackgroundColor
        backgroundView.layer.cornerRadius = 10
        stack.addSubview(backgroundView)
        stack.sendSubviewToBack(backgroundView)
        backgroundView.autoPinEdgesToSuperviewEdges()

        return stack
    }

    private static func buildBalanceConversionText(paymentBalance: PaymentBalance) -> String? {
        let localCurrencyCode = paymentsCurrencies.currentCurrencyCode
        guard let currencyConversionInfo = paymentsCurrencies.conversionInfo(forCurrencyCode: localCurrencyCode)  else {
            return nil
        }
        guard let fiatAmountString = PaymentsFormat.formatAsFiatCurrency(paymentAmount: paymentBalance.amount,
                                                                       currencyConversionInfo: currencyConversionInfo) else {
            return nil
        }

        // NOTE: conversion freshness is different than the balance freshness.
        //
        // We format the conversion freshness date using the local locale.
        // We format the currency using the EN/US locale.
        //
        // It is sufficient to format as a time, currency conversions go stale in less than a day.
        let conversionFreshnessString = DateUtil.formatDate(asTime: currencyConversionInfo.conversionDate)
        let formatString = NSLocalizedString("SETTINGS_PAYMENTS_BALANCE_CONVERSION_FORMAT",
                                             comment: "Format string for the 'local balance converted into local currency' indicator. Embeds: {{ %1$@ the local balance in the local currency, %2$@ the local currency code, %3$@ the date the currency conversion rate was obtained. }}..")
        return String(format: formatString, fiatAmountString, localCurrencyCode, conversionFreshnessString)
    }

    private func configureHistorySection(_ section: OWSTableSection,
                                         paymentsHistoryDataSource: PaymentsHistoryDataSource) {

        guard paymentsHistoryDataSource.hasItems else {
            section.hasBackground = false
            section.add(OWSTableItem(customCellBlock: {
                let cell = OWSTableItem.newCell()

                let label = UILabel()
                label.text = NSLocalizedString("SETTINGS_PAYMENTS_NO_ACTIVITY_INDICATOR",
                                               comment: "Message indicating that there is no payment activity to display in the payment settings.")
                label.textColor = Theme.secondaryTextAndIconColor
                label.font = UIFont.ows_dynamicTypeBodyClamped
                label.numberOfLines = 0
                label.lineBreakMode = .byWordWrapping
                label.textAlignment = .center

                let stack = UIStackView(arrangedSubviews: [label])
                stack.axis = .vertical
                stack.alignment = .fill
                stack.layoutMargins = UIEdgeInsets(top: 10, leading: 0, bottom: 30, trailing: 0)
                stack.isLayoutMarginsRelativeArrangement = true

                cell.contentView.addSubview(stack)
                stack.autoPinEdgesToSuperviewMargins()

                return cell
            },
            actionBlock: nil))
            return
        }

        section.headerTitle = NSLocalizedString("SETTINGS_PAYMENTS_RECENT_PAYMENTS",
                                                comment: "Label for the 'recent payments' section in the payment settings.")

        section.separatorInsetLeading = NSNumber(value: Double(OWSTableViewController2.cellHInnerMargin +
                                                                PaymentModelCell.separatorInsetLeading))

        var hasMoreItems = false
        for (index, paymentItem) in paymentsHistoryDataSource.items.enumerated() {
            guard index < PaymentsSettingsViewController.maxHistoryCount else {
                hasMoreItems = true
                break
            }
            section.add(OWSTableItem(customCellBlock: {
                let cell = PaymentModelCell()
                cell.configure(paymentItem: paymentItem)
                return cell
            },
            actionBlock: { [weak self] in
                self?.didTapPaymentItem(paymentItem: paymentItem)
            }))
        }

        if hasMoreItems {
            section.add(OWSTableItem(customCellBlock: {
                let cell = OWSTableItem.newCell()
                cell.selectionStyle = .none

                let label = UILabel()
                label.text = NSLocalizedString("SETTINGS_PAYMENTS_SHOW_ALL_PAYMENTS_BUTTON",
                                               comment: "Label for the 'show all payments' button in the payment settings.")
                label.font = .ows_dynamicTypeBodyClamped
                label.textColor = Theme.primaryTextColor

                let stack = UIStackView(arrangedSubviews: [label])
                stack.axis = .vertical
                stack.alignment = .fill
                cell.contentView.addSubview(stack)
                stack.autoPinEdgesToSuperviewMargins()
                stack.layoutMargins = UIEdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0)
                stack.isLayoutMarginsRelativeArrangement = true

                cell.accessoryType = .disclosureIndicator
                return cell
            },
            actionBlock: { [weak self] in
                self?.showPaymentsHistoryView()
            }))
        }
    }

    private func updateTableContentsNotEnabled() {
        AssertIsOnMainThread()

        let contents = OWSTableContents()

        let headerSection = OWSTableSection()
        headerSection.add(OWSTableItem(customCellBlock: { [weak self] in
            let cell = OWSTableItem.newCell()
            self?.configureNotEnabledCell(cell)
            return cell
        },
        actionBlock: nil))
        contents.addSection(headerSection)

        addHelpCards(contents: contents)

        self.contents = contents
    }

    private func configureNotEnabledCell(_ cell: UITableViewCell) {

        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString("SETTINGS_PAYMENTS_OPT_IN_TITLE",
                                            comment: "Title for the 'payments opt-in' view in the app settings.")
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.font = UIFont.ows_dynamicTypeBodyClamped.ows_semibold
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.textAlignment = .center

        let heroImageView = AnimationView(name: "activate-payments")
        heroImageView.contentMode = .scaleAspectFit
        let viewSize = view.bounds.size
        let heroSize = min(viewSize.width, viewSize.height) * 0.5
        heroImageView.autoSetDimension(.height, toSize: heroSize)

        let bodyLabel = UILabel()
        bodyLabel.text = NSLocalizedString("SETTINGS_PAYMENTS_OPT_IN_MESSAGE",
                                           comment: "Message for the 'payments opt-in' view in the app settings.")
        bodyLabel.textColor = Theme.secondaryTextAndIconColor
        bodyLabel.font = UIFont.ows_dynamicTypeSubheadlineClamped
        bodyLabel.textAlignment = .center
        bodyLabel.numberOfLines = 0
        bodyLabel.lineBreakMode = .byWordWrapping

        let buttonTitle = NSLocalizedString("SETTINGS_PAYMENTS_OPT_IN_ACTIVATE_BUTTON",
                                            comment: "Label for 'activate' button in the 'payments opt-in' view in the app settings.")
        let activateButton = OWSFlatButton.button(title: buttonTitle,
                                                  font: UIFont.ows_dynamicTypeBody.ows_semibold,
                                                  titleColor: .white,
                                                  backgroundColor: .ows_accentBlue,
                                                  target: self,
                                                  selector: #selector(didTapEnablePaymentsButton))
        activateButton.autoSetHeightUsingFont()

        let stack = UIStackView(arrangedSubviews: [
            titleLabel,
            UIView.spacer(withHeight: 24),
            heroImageView,
            UIView.spacer(withHeight: 20),
            bodyLabel,
            UIView.spacer(withHeight: 20),
            activateButton
        ])

        if Self.payments.paymentsEntropy == nil {
            let buttonTitle = NSLocalizedString("SETTINGS_PAYMENTS_RESTORE_PAYMENTS_BUTTON",
                                                comment: "Label for 'restore payments' button in the payments settings.")
            let restorePaymentsButton = OWSFlatButton.button(title: buttonTitle,
                                                             font: UIFont.ows_dynamicTypeBody.ows_semibold,
                                                             titleColor: .ows_accentBlue,
                                                             backgroundColor: self.tableBackgroundColor,
                                                             target: self,
                                                             selector: #selector(didTapRestorePaymentsButton))
            restorePaymentsButton.autoSetHeightUsingFont()
            stack.addArrangedSubviews([
                UIView.spacer(withHeight: 8),
                restorePaymentsButton
            ])
        }

        stack.axis = .vertical
        stack.alignment = .fill
        stack.layoutMargins = UIEdgeInsets(top: 20, leading: 0, bottom: 32, trailing: 0)
        stack.isLayoutMarginsRelativeArrangement = true
        cell.contentView.addSubview(stack)
        stack.autoPinEdgesToSuperviewMargins()
    }

    private func addHelpCards(contents: OWSTableContents) {
        contents.addSection(buildHelpCard(title: NSLocalizedString("SETTINGS_PAYMENTS_HELP_CARD_ABOUT_MOBILECOIN_TITLE",
                                                                   comment: "Title for the 'About MobileCoin' help card in the payments settings."),
                                          body: NSLocalizedString("SETTINGS_PAYMENTS_HELP_CARD_ABOUT_MOBILECOIN_DESCRIPTION",
                                                                  comment: "Description for the 'About MobileCoin' help card in the payments settings."),
                                          iconName: "about-mobilecoin",
                                          selector: #selector(didTapAboutMobileCoinCard)))

        contents.addSection(buildHelpCard(title: NSLocalizedString("SETTINGS_PAYMENTS_HELP_CARD_ADDING_TO_YOUR_WALLET_TITLE",
                                                                   comment: "Title for the 'Adding to your wallet' help card in the payments settings."),
                                          body: NSLocalizedString("SETTINGS_PAYMENTS_HELP_CARD_ADDING_TO_YOUR_WALLET_DESCRIPTION",
                                                                  comment: "Description for the 'Adding to your wallet' help card in the payments settings."),
                                          iconName: "add-money",
                                          selector: #selector(didTapAddingToYourWalletCard)))

        contents.addSection(buildHelpCard(title: NSLocalizedString("SETTINGS_PAYMENTS_HELP_CARD_CASHING_OUT_TITLE",
                                                                   comment: "Title for the 'Cashing Out' help card in the payments settings."),
                                          body: NSLocalizedString("SETTINGS_PAYMENTS_HELP_CARD_CASHING_OUT_DESCRIPTION",
                                                                  comment: "Description for the 'Cashing Out' help card in the payments settings."),
                                          iconName: "cash-out",
                                          selector: #selector(didTapCashingOutCoinCard)))
    }

    // TODO: How do we remove help cards?
    // TODO: What are the links for the help cards?
    // TODO: What are the "learn more" behaviors?
    private func buildHelpCard(title: String,
                               body: String,
                               iconName: String,
                               selector: Selector) -> OWSTableSection {
        let section = OWSTableSection()

        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: selector)

        section.add(OWSTableItem(customCellBlock: {
            let titleLabel = UILabel()
            titleLabel.text = title
            titleLabel.textColor = Theme.primaryTextColor
            titleLabel.font = UIFont.ows_dynamicTypeBodyClamped.ows_semibold

            let bodyLabel = UILabel()
            bodyLabel.text = body
            bodyLabel.textColor = Theme.secondaryTextAndIconColor
            bodyLabel.font = UIFont.ows_dynamicTypeBody2Clamped
            bodyLabel.numberOfLines = 0
            bodyLabel.lineBreakMode = .byWordWrapping

            let learnMoreLabel = UILabel()
            learnMoreLabel.text = CommonStrings.learnMore
            learnMoreLabel.textColor = Theme.accentBlueColor
            learnMoreLabel.font = UIFont.ows_dynamicTypeSubheadlineClamped

            let animationView = AnimationView(name: iconName)
            animationView.contentMode = .scaleAspectFit
            animationView.autoSetDimensions(to: .square(80))

            let vStack = UIStackView(arrangedSubviews: [
                titleLabel,
                bodyLabel,
                learnMoreLabel
            ])
            vStack.axis = .vertical
            vStack.alignment = .leading
            vStack.spacing = 8

            let hStack = UIStackView(arrangedSubviews: [
                vStack,
                animationView
            ])
            hStack.axis = .horizontal
            hStack.alignment = .center
            hStack.spacing = 16

            let cell = OWSTableItem.newCell()
            cell.contentView.addSubview(hStack)
            hStack.autoPinEdgesToSuperviewMargins()

            cell.isUserInteractionEnabled = true
            cell.addGestureRecognizer(tapGestureRecognizer)

            return cell
        },
        actionBlock: { [weak self] in
            self?.perform(selector)
        }))

        return section
    }

    // MARK: -

    private func showSettingsActionSheet() {
        let actionSheet = ActionSheetController(title: nil, message: nil)

        actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("SETTINGS_PAYMENTS_TRANSFER_TO_EXCHANGE",
                                                                         comment: "Label for the 'transfer to exchange' button in the payment settings."),
                                                accessibilityIdentifier: "payments.settings.transfer_to_exchange",
                                                style: .default) { [weak self] _ in
            self?.didTapTransferToExchangeButton()
        })

        actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("SETTINGS_PAYMENTS_SET_CURRENCY",
                                                                         comment: "Title for the 'set currency' view in the app settings."),
                                                accessibilityIdentifier: "payments.settings.set_currency",
                                                style: .default) { [weak self] _ in
            self?.didTapSetCurrencyButton()
        })

        actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("SETTINGS_PAYMENTS_DEACTIVATE_PAYMENTS",
                                                                         comment: "Label for 'deactivate payments' button in the app settings."),
                                                accessibilityIdentifier: "payments.settings.deactivate_payments",
                                                style: .default) { [weak self] _ in
            self?.didTapDeactivatePaymentsButton()
        })

        actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("SETTINGS_PAYMENTS_VIEW_RECOVERY_PASSPHRASE",
                                                                         comment: "Label for 'view payments recovery passphrase' button in the app settings."),
                                                accessibilityIdentifier: "payments.settings.view_recovery_passphrase",
                                                style: .default) { [weak self] _ in
            self?.didTapViewPaymentsPassphraseButton()
        })

        // TODO: Design: do we still need this?
        actionSheet.addAction(ActionSheetAction(title: CommonStrings.help,
                                                accessibilityIdentifier: "payments.settings.help",
                                                style: .default) { [weak self] _ in
            self?.didTapHelpButton()
        })

        actionSheet.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheet)
    }

    private func showConfirmDeactivatePaymentsUI() {
        let actionSheet = ActionSheetController(title: NSLocalizedString("SETTINGS_PAYMENTS_DEACTIVATE_PAYMENTS_CONFIRM_TITLE",
                                                                         comment: "Title for the 'deactivate payments confirmation' UI in the payment settings."),
                                                message: NSLocalizedString("SETTINGS_PAYMENTS_DEACTIVATE_PAYMENTS_CONFIRM_DESCRIPTION",
                                                                           comment: "Description for the 'deactivate payments confirmation' UI in the payment settings."))

        actionSheet.addAction(ActionSheetAction(title: CommonStrings.continueButton,
                                                accessibilityIdentifier: "payments.settings.deactivate.continue",
                                                style: .default) { [weak self] _ in
            self?.didTapConfirmDeactivatePaymentsButton()
        })

        actionSheet.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheet)
    }

    // MARK: - Events

    @objc
    func didTapDismiss() {
        dismiss(animated: true, completion: nil)
    }

    @objc
    func didTapEnablePaymentsButton(_ sender: UIButton) {
        AssertIsOnMainThread()

        databaseStorage.asyncWrite { transaction in
            Self.paymentsSwift.enablePayments(transaction: transaction)

            transaction.addAsyncCompletion {
                self.showPaymentsActivatedToast()
            }
        }
    }

    private func showPaymentsActivatedToast() {
        AssertIsOnMainThread()
        let toastText = NSLocalizedString("SETTINGS_PAYMENTS_OPT_IN_ACTIVATED_TOAST",
                                          comment: "Message shown when payments rae activated in the 'payments opt-in' view in the app settings.")
        self.presentToast(text: toastText)
    }

    @objc
    func didTapRestorePaymentsButton() {
        AssertIsOnMainThread()

        guard Self.payments.paymentsEntropy == nil else {
            owsFailDebug("paymentsEntropy already set.")
            return
        }

        let view = PaymentsRestoreWalletSplashViewController(restoreWalletDelegate: self)
        let navigationVC = OWSNavigationController(rootViewController: view)
        present(navigationVC, animated: true)
    }

    @objc
    func didTapSettings() {
        showSettingsActionSheet()
    }

    private func didTapSetCurrencyButton() {
        let view = PaymentsCurrencyViewController()
        navigationController?.pushViewController(view, animated: true)
    }

    private func didTapViewPaymentsPassphraseButton() {
        guard let passphrase = paymentsSwift.passphrase else {
            owsFailDebug("Missing passphrase.")
            return
        }
        let shouldShowConfirm = !hasReviewedPassphraseWithSneakyTransaction()
        let view = PaymentsViewPassphraseSplashViewController(passphrase: passphrase,
                                                              shouldShowConfirm: shouldShowConfirm,
                                                              viewPassphraseDelegate: self)
        let navigationVC = OWSNavigationController(rootViewController: view)
        present(navigationVC, animated: true)
    }

    private func didTapDeactivatePaymentsButton() {
        showConfirmDeactivatePaymentsUI()
    }

    private func didTapConfirmDeactivatePaymentsButton() {
        guard let paymentBalance = self.paymentsSwift.currentPaymentBalance else {
            // TODO: Need copy.
            OWSActionSheets.showErrorAlert(message: NSLocalizedString("SETTINGS_PAYMENTS_CANNOT_DEACTIVATE_PAYMENTS_NO_BALANCE",
                                                                      comment: "Error message indicating that payments could not be deactivated because the current balance is unavailable."))
            return
        }
        guard paymentBalance.amount.picoMob > 0 else {
            databaseStorage.write { transaction in
                Self.paymentsSwift.disablePayments(transaction: transaction)
            }
            return
        }
        let vc = PaymentsDeactivateViewController(paymentBalance: paymentBalance)
        let navigationVC = OWSNavigationController(rootViewController: vc)
        present(navigationVC, animated: true)
    }

    private func didTapHelpButton() {
        // TODO: Pending design/support URL.
    }

    private func didTapTransferToExchangeButton() {
        let view = PaymentsTransferOutViewController(transferAmount: nil)
        let navigationController = OWSNavigationController(rootViewController: view)
        present(navigationController, animated: true, completion: nil)
    }

    private func showPaymentsHistoryView() {
        let view = PaymentsHistoryViewController()
        navigationController?.pushViewController(view, animated: true)
    }

    @objc
    func didTapAddMoneyButton(sender: UIGestureRecognizer) {
        let view = PaymentsTransferInViewController()
        let navigationController = OWSNavigationController(rootViewController: view)
        present(navigationController, animated: true, completion: nil)
    }

    @objc
    func didTapSendPaymentButton(sender: UIGestureRecognizer) {
        PaymentsSendRecipientViewController.presentAsFormSheet(fromViewController: self,
                                                               paymentRequestModel: nil)
    }

    private func didTapPaymentItem(paymentItem: PaymentsHistoryItem) {
        let view = PaymentsDetailViewController(paymentItem: paymentItem)
        navigationController?.pushViewController(view, animated: true)
    }

    @objc
    private func didTapAboutMobileCoinCard() {
        // TODO: Pending design/support URL.
    }

    @objc
    private func didTapAddingToYourWalletCard() {
        // TODO: Pending design/support URL.
    }

    @objc
    private func didTapCashingOutCoinCard() {
        // TODO: Pending design/support URL.
    }
}

// MARK: -

extension PaymentsSettingsViewController: PaymentsHistoryDataSourceDelegate {
    var recordType: PaymentsHistoryDataSource.RecordType {
        .all
    }

    var maxRecordCount: Int? {
        // Load an extra item so we can detect if there's more items
        // to render.
        Self.maxHistoryCount + 1
    }

    func didUpdateContent() {
        AssertIsOnMainThread()

        updateTableContents()
    }
}

// MARK: -

extension PaymentsSettingsViewController: PaymentsViewPassphraseDelegate {

    private static let keyValueStore = SDSKeyValueStore(collection: "PaymentSettings")
    private static let hasReviewedPassphraseKey = "hasReviewedPassphrase"

    private func hasReviewedPassphraseWithSneakyTransaction() -> Bool {
        databaseStorage.read { transaction in
            Self.keyValueStore.getBool(Self.hasReviewedPassphraseKey,
                                       defaultValue: false,
                                       transaction: transaction)
        }
    }

    private func setHasReviewedPassphraseWithSneakyTransaction() {
        databaseStorage.write { transaction in
            Self.keyValueStore.setBool(true,
                                       key: Self.hasReviewedPassphraseKey,
                                       transaction: transaction)
        }
    }

    public func viewPassphraseDidComplete() {
        if !hasReviewedPassphraseWithSneakyTransaction() {
            setHasReviewedPassphraseWithSneakyTransaction()

            presentToast(text: NSLocalizedString("SETTINGS_PAYMENTS_VIEW_PASSPHRASE_COMPLETE_TOAST",
                                                 comment: "Message indicating that 'payments passphrase review' is complete."))
        }
    }
}

// MARK: -

extension PaymentsSettingsViewController: PaymentsRestoreWalletDelegate {

    public func restoreWalletDidComplete() {
        presentToast(text: NSLocalizedString("SETTINGS_PAYMENTS_RESTORE_WALLET_COMPLETE_TOAST",
                                             comment: "Message indicating that 'restore payments wallet' is complete."))
    }
}
