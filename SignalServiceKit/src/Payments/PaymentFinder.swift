//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

@objc
public class PaymentFinder: NSObject {

    public class func paymentModels(paymentStates: [TSPaymentState],
                                     transaction: SDSAnyReadTransaction) -> [TSPaymentModel] {
        switch transaction.readTransaction {
        case .grdbRead(let grdbTransaction):
            return paymentModels(paymentStates: paymentStates, grdbTransaction: grdbTransaction)
        case .yapRead:
            owsFail("Invalid transaction.")
        }
    }

    private class func paymentModels(paymentStates: [TSPaymentState],
                                      grdbTransaction transaction: GRDBReadTransaction) -> [TSPaymentModel] {

        let paymentStatesToLookup = paymentStates.compactMap { $0.rawValue }.map { "\($0)" }.joined(separator: ",")

        let sql = """
        SELECT * FROM \(PaymentModelRecord.databaseTableName)
        WHERE \(paymentModelColumn: .paymentState) IN (\(paymentStatesToLookup))
        """
        let cursor = TSPaymentModel.grdbFetchCursor(sql: sql, arguments: [], transaction: transaction)

        var paymentModels = [TSPaymentModel]()
        do {
            while let paymentModel = try cursor.next() {
                paymentModels.append(paymentModel)
            }
        } catch {
            owsFailDebug("unexpected error \(error)")
        }
        return paymentModels
    }

    public class func paymentModel(forMCIncomingTransaction mcIncomingTransaction: Data,
                                   transaction: SDSAnyReadTransaction) -> TSPaymentModel? {
        guard !mcIncomingTransaction.isEmpty else {
            owsFailDebug("Invalid mcIncomingTransaction.")
            return nil
        }
        let sql = """
        SELECT * FROM \(PaymentModelRecord.databaseTableName)
        WHERE \(paymentModelColumn: .mcIncomingTransaction) = ?
        LIMIT 1
        """
        let arguments: StatementArguments = [mcIncomingTransaction]
        return TSPaymentModel.grdbFetchOne(sql: sql,
                                           arguments: arguments,
                                           transaction: transaction.unwrapGrdbRead)
    }

    @objc
    public class func firstUnreadPaymentModel(transaction: SDSAnyReadTransaction) -> TSPaymentModel? {
        let sql = """
        SELECT * FROM \(PaymentModelRecord.databaseTableName)
        WHERE \(paymentModelColumn: .isUnread) = 1
        LIMIT 1
        """
        return TSPaymentModel.grdbFetchOne(sql: sql,
                                           arguments: [],
                                           transaction: transaction.unwrapGrdbRead)
    }

    @objc
    public class func allUnreadPaymentModels(transaction: SDSAnyReadTransaction) -> [TSPaymentModel] {
        let sql = """
        SELECT * FROM \(PaymentModelRecord.databaseTableName)
        WHERE \(paymentModelColumn: .isUnread) = 1
        """
        do {
            return try TSPaymentModel.grdbFetchCursor(sql: sql,
                                                      arguments: [],
                                                      transaction: transaction.unwrapGrdbRead).all()
        } catch {
            owsFail("error: \(error)")
        }
    }

    @objc
    public class func unreadCount(transaction: SDSAnyReadTransaction) -> UInt {
        do {
            guard let count = try UInt.fetchOne(transaction.unwrapGrdbRead.database,
                                                sql: """
                SELECT COUNT(*)
                FROM \(PaymentModelRecord.databaseTableName)
                WHERE \(paymentModelColumn: .isUnread) = 1
                """,
                                                arguments: []) else {
                throw OWSAssertionError("count was unexpectedly nil")
            }
            return count
        } catch {
            owsFail("error: \(error)")
        }
    }

    // MARK: -

    public class func paymentRequestModel(forRequestUuidString requestUuidString: String,
                                          transaction: SDSAnyReadTransaction) -> TSPaymentRequestModel? {
        guard !requestUuidString.isEmpty else {
            owsFailDebug("Invalid requestUuidString.")
            return nil
        }
        let sql = """
        SELECT * FROM \(PaymentRequestModelRecord.databaseTableName)
        WHERE \(paymentRequestModelColumn: .requestUuidString) = ?
        LIMIT 1
        """
        let arguments: StatementArguments = [requestUuidString]
        return TSPaymentRequestModel.grdbFetchOne(sql: sql,
                                                  arguments: arguments,
                                                  transaction: transaction.unwrapGrdbRead)
    }

    @objc
    public class func paymentModels(forMcLedgerBlockIndex mcLedgerBlockIndex: UInt64,
                                    transaction: SDSAnyReadTransaction) -> [TSPaymentModel] {
        let sql = """
        SELECT * FROM \(PaymentModelRecord.databaseTableName)
        WHERE \(paymentModelColumn: .mcLedgerBlockIndex) = ?
        """
        do {
            return try TSPaymentModel.grdbFetchCursor(sql: sql,
                                                      arguments: [mcLedgerBlockIndex],
                                                      transaction: transaction.unwrapGrdbRead).all()
        } catch {
            owsFail("error: \(error)")
        }
    }
}
